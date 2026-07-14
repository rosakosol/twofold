//
//  WidgetSnapshotWriter.swift
//  Twofold
//
//  Main-app-only — builds a WidgetSnapshot from live AppModel state and hands it to WidgetKit.
//  This is the sole place that talks to WeatherKit and downloads the latest memory photo on
//  the widgets' behalf, so no widget extension needs its own WeatherKit entitlement or a
//  second call against Supabase's private memory-photos bucket.
//

import Foundation
import MapKit
import SwiftUI
import UIKit
import WidgetKit

enum WidgetSnapshotWriter {
    /// Opportunistic — called on relevant AppModel mutations and on scenePhase becoming
    /// active, not on any fixed schedule. Weather can go stale if the app isn't opened for a
    /// while; acceptable for v1 (see the Settings/Widgets plan's Architecture decisions).
    static func refresh(appModel: AppModel) async {
        guard appModel.partnerConnected else {
            WidgetSnapshot.write(
                WidgetSnapshot(
                    myID: nil,
                    myName: appModel.currentUser.name,
                    partnerName: appModel.partner.name,
                    partnerCity: nil,
                    partnerTimeZoneIdentifier: nil,
                    anniversaryDate: nil,
                    subscriptionTier: appModel.subscriptionTier,
                    nextFlight: nil,
                    latestMemory: nil,
                    partnerWeather: nil,
                    relationshipStats: nil,
                    travelStats: nil,
                    coupleID: nil,
                    partnerID: nil,
                    writtenAt: .now,
                    globeImageWrittenAt: nil
                )
            )
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        let partnerCity = appModel.partner.homeCity

        if let avatarURL = appModel.currentUser.avatarURL, let data = try? await URLSession.shared.data(from: avatarURL).0 {
            WidgetImageCache.writeMyAvatarImage(data)
        }
        if let avatarURL = appModel.partner.avatarURL, let data = try? await URLSession.shared.data(from: avatarURL).0 {
            WidgetImageCache.writePartnerAvatarImage(data)
        }

        var flightInfo: WidgetSnapshot.FlightInfo?
        if let flight = appModel.activeOrUpcomingFlight {
            let hasDeparted = (flight.bestDeparture ?? .distantFuture) <= .now
            flightInfo = WidgetSnapshot.FlightInfo(
                id: flight.id,
                status: flight.status,
                originCity: flight.origin.displayName,
                destinationCity: flight.destination.displayName,
                bestDeparture: flight.bestDeparture,
                bestArrival: flight.bestArrival,
                delaySeconds: hasDeparted ? flight.arrivalDelaySeconds : flight.departureDelaySeconds,
                flightNumber: flight.displayNumber,
                airlineName: flight.airlineName,
                originCoordinate: flight.origin.coordinate.map { WidgetCoordinate(latitude: $0.latitude, longitude: $0.longitude) },
                destinationCoordinate: flight.destination.coordinate.map { WidgetCoordinate(latitude: $0.latitude, longitude: $0.longitude) },
                positionCoordinate: flight.positionCoordinate.map { WidgetCoordinate(latitude: $0.latitude, longitude: $0.longitude) },
                progress: flight.progress,
                travelerIsMe: flight.travelerIDs.isEmpty ? nil : flight.travelerIDs.contains(appModel.currentUser.id)
            )
            if let logoURL = flight.displayLogoURL, let data = try? await URLSession.shared.data(from: logoURL).0 {
                WidgetImageCache.writeAirlineLogoImage(data)
            }
            await refreshFlightMapImage(flight: flight, travelerIsMe: flightInfo?.travelerIsMe)
        } else {
            WidgetImageCache.clearFlightMapImage()
        }

        var memoryInfo: WidgetSnapshot.MemoryInfo?
        if let latestMemory = appModel.memories.max(by: { $0.date < $1.date }) {
            memoryInfo = WidgetSnapshot.MemoryInfo(id: latestMemory.id, title: latestMemory.title, date: latestMemory.date)
            if let photoURL = latestMemory.photoURL, let data = try? await URLSession.shared.data(from: photoURL).0 {
                WidgetImageCache.writeLatestMemoryImage(data)
            }
        } else {
            WidgetImageCache.clearLatestMemoryImage()
        }

        var weatherInfo: WidgetSnapshot.WeatherInfo?
        if let partnerCity, let reading = await TwofoldWeatherService.currentWeather(for: partnerCity) {
            weatherInfo = WidgetSnapshot.WeatherInfo(symbolName: reading.symbolName, temperatureC: reading.temperatureC)
        }

        let relationshipStats = WidgetSnapshot.RelationshipStats(
            memoryCount: appModel.memories.count,
            tripCount: appModel.trips.count
        )

        let flightStats = FlightStats(trips: appModel.trips, couple: appModel.couple)
        let nextTrip = appModel.upcomingTrips.first
        let travelStats = WidgetSnapshot.TravelStats(
            flightCount: flightStats.flightCount,
            countryCount: flightStats.countries.count,
            totalDistanceKm: flightStats.totalDistanceKm,
            nextTripDestination: nextTrip?.destination.city,
            nextTripDate: nextTrip?.departureDate
        )

        let globeImageWrittenAt = await refreshGlobeImageIfNeeded(appModel: appModel)

        WidgetSnapshot.write(
            WidgetSnapshot(
                myID: appModel.currentUser.id,
                myName: appModel.currentUser.name,
                partnerName: appModel.partner.name,
                partnerCity: partnerCity?.city,
                partnerTimeZoneIdentifier: partnerCity?.timeZoneIdentifier,
                anniversaryDate: appModel.couple.startedDatingOn,
                subscriptionTier: appModel.subscriptionTier,
                nextFlight: flightInfo,
                latestMemory: memoryInfo,
                partnerWeather: weatherInfo,
                relationshipStats: relationshipStats,
                travelStats: travelStats,
                coupleID: appModel.couple.id,
                partnerID: appModel.partner.id,
                writtenAt: .now,
                globeImageWrittenAt: globeImageWrittenAt
            )
        )
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Bakes a route line + endpoint dots + traveler marker directly onto a real MKMapSnapshotter
    /// basemap into one flattened image, using `MKMapSnapshotter.Snapshot.point(for:)` to convert
    /// coordinates to pixel positions at write time — the widget just displays the result, no
    /// need to replicate the snapshotter's region/projection math on the extension side to
    /// re-derive marker positions itself.
    private static func refreshFlightMapImage(flight: Flight, travelerIsMe: Bool?) async {
        // `.isFinite` on top of the plain nil-check: `origin`/`destination` come straight off
        // whatever AeroAPI or a self-reported flight last supplied, and a NaN/infinite latitude
        // or longitude (garbage upstream data, not a normal "not resolved yet" case — that's
        // nil, already handled) would flow straight into `MKCoordinateRegion` below and crash
        // MapKit outright rather than throwing a catchable error.
        guard let origin = flight.origin.coordinate, let destination = flight.destination.coordinate,
              origin.latitude.isFinite, origin.longitude.isFinite,
              destination.latitude.isFinite, destination.longitude.isFinite else {
            WidgetImageCache.clearFlightMapImage()
            return
        }

        let minLat = min(origin.latitude, destination.latitude)
        let maxLat = max(origin.latitude, destination.latitude)

        // A route crossing the antimeridian (e.g. Tokyo→LA, origin ~140°E, destination ~120°W)
        // has a naive |maxLon - minLon| over 180° — the "short way" actually wraps the other
        // side of the globe. Unwrap one endpoint the same way FlightMapView.routeSamples does
        // before taking min/max, then normalize the resulting center back into ±180° since
        // (unlike MapLibre) MKCoordinateRegion expects a standard-range center longitude.
        var destinationLongitude = destination.longitude
        if destinationLongitude - origin.longitude > 180 {
            destinationLongitude -= 360
        } else if destinationLongitude - origin.longitude < -180 {
            destinationLongitude += 360
        }
        let minLon = min(origin.longitude, destinationLongitude)
        let maxLon = max(origin.longitude, destinationLongitude)

        var centerLongitude = (minLon + maxLon) / 2
        if centerLongitude > 180 { centerLongitude -= 360 }
        if centerLongitude < -180 { centerLongitude += 360 }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: centerLongitude)

        // 1.6x the raw span so both endpoints sit comfortably inside the frame, with a floor so
        // short domestic hops don't zoom in so far the basemap looks empty/blank, and a ceiling
        // (MKCoordinateRegion crashes on a span that isn't a valid region, e.g. > 360°) — a span
        // this wide is already a "whole world" view regardless of the exact route.
        let span = MKCoordinateSpan(
            latitudeDelta: min(170, max(4, (maxLat - minLat) * 1.6)),
            longitudeDelta: min(170, max(4, (maxLon - minLon) * 1.6))
        )

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: span)
        options.size = CGSize(width: 600, height: 400)
        options.mapType = .mutedStandard
        options.showsBuildings = false

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else {
            return
        }

        let markerImageData: Data? = {
            switch travelerIsMe {
            case true: WidgetImageCache.readMyAvatarImage()
            case false: WidgetImageCache.readPartnerAvatarImage()
            case nil: nil
            }
        }()
        let markerImage = markerImageData.flatMap(UIImage.init(data:))

        // Pre-departure/post-arrival there's no live position from the provider — park the
        // marker at the origin or destination, mirroring FlightMapView's own fallback, rather
        // than lerping progress along a straight line that doesn't match the real great-circle
        // route curve.
        let markerCoordinate: CLLocationCoordinate2D
        if let position = flight.positionCoordinate {
            markerCoordinate = position
        } else {
            markerCoordinate = flight.progress >= 1 ? destination : origin
        }

        let renderer = UIGraphicsImageRenderer(size: options.size)
        let composed = renderer.image { context in
            snapshot.image.draw(at: .zero)
            let cg = context.cgContext

            let originPoint = snapshot.point(for: origin)
            let destinationPoint = snapshot.point(for: destination)

            cg.setLineCap(.round)
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(5)
            cg.move(to: originPoint)
            cg.addLine(to: destinationPoint)
            cg.strokePath()

            cg.setStrokeColor(UIColor(Theme.skyBlue).cgColor)
            cg.setLineWidth(3)
            cg.move(to: originPoint)
            cg.addLine(to: destinationPoint)
            cg.strokePath()

            for point in [originPoint, destinationPoint] {
                let dot = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
                cg.setFillColor(UIColor(Theme.subtleInk).cgColor)
                cg.fillEllipse(in: dot)
                cg.setStrokeColor(UIColor.white.cgColor)
                cg.setLineWidth(2.5)
                cg.strokeEllipse(in: dot)
            }

            let markerPoint = snapshot.point(for: markerCoordinate)
            if let markerImage {
                let size: CGFloat = 40
                let rect = CGRect(x: markerPoint.x - size / 2, y: markerPoint.y - size / 2, width: size, height: size)
                cg.saveGState()
                cg.setStrokeColor(UIColor.white.cgColor)
                cg.setLineWidth(3)
                let ring = UIBezierPath(ovalIn: rect.insetBy(dx: -1.5, dy: -1.5))
                cg.addPath(ring.cgPath)
                cg.strokePath()
                let clip = UIBezierPath(ovalIn: rect)
                clip.addClip()
                markerImage.draw(in: rect)
                cg.restoreGState()
            } else {
                let size: CGFloat = 28
                let rect = CGRect(x: markerPoint.x - size / 2, y: markerPoint.y - size / 2, width: size, height: size)
                cg.setFillColor(UIColor(flight.status.semanticColor).cgColor)
                cg.fillEllipse(in: rect)
                if let planeImage = UIImage(systemName: "airplane")?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                    let iconSize: CGFloat = 14
                    planeImage.draw(in: CGRect(x: markerPoint.x - iconSize / 2, y: markerPoint.y - iconSize / 2, width: iconSize, height: iconSize))
                }
            }
        }

        if let data = composed.jpegData(compressionQuality: 0.75) {
            WidgetImageCache.writeFlightMapImage(data)
        }
    }

    /// GlobeWidget is Premium-only and its content barely changes day to day, so this only
    /// actually runs MKMapSnapshotter (expensive, unbounded-latency — see SnapshotShareView's
    /// own use of it) for Premium subscribers, and at most once/24h. Returns the timestamp to
    /// carry forward into the new snapshot — unchanged if this refresh was skipped.
    private static func refreshGlobeImageIfNeeded(appModel: AppModel) async -> Date? {
        let previousWrittenAt = WidgetSnapshot.read()?.globeImageWrittenAt
        guard appModel.subscriptionTier == WidgetTier.premium else { return previousWrittenAt }
        if let previousWrittenAt, previousWrittenAt.timeIntervalSinceNow > -86400 {
            return previousWrittenAt
        }

        // A `region`-based snapshot (what this used before) always renders a flat, equirectangular
        // crop — no amount of span produces sphere curvature. The actual "globe" look (used live
        // by RelationshipGlobeView) only comes from a `camera` far enough away that MapKit's
        // renderer switches to its 3D-sphere projection; MKMapSnapshotter supports that same
        // camera-based rendering, just via `options.camera` instead of `options.region`.
        let center = Self.globeCenter(appModel: appModel)
        let options = MKMapSnapshotter.Options()
        options.mapType = .satellite
        options.camera = MKMapCamera(lookingAtCenter: center, fromDistance: 22_000_000, pitch: 0, heading: 0)
        options.size = CGSize(width: 500, height: 500)
        options.showsBuildings = false

        guard let snapshot = try? await MKMapSnapshotter(options: options).start(),
              let data = snapshot.image.jpegData(compressionQuality: 0.6) else {
            return previousWrittenAt
        }
        WidgetImageCache.writeGlobeImage(data)
        return .now
    }

    /// The couple's real spherical midpoint when both home cities are known (same "average
    /// unit-vector on the sphere" math as RelationshipGlobeView.midpoint(_:_:), so the globe
    /// widget centers on something relevant to them) — falls back to a wide Atlantic view when
    /// one or both cities aren't set yet.
    private static func globeCenter(appModel: AppModel) -> CLLocationCoordinate2D {
        guard let cityA = appModel.currentUser.homeCity, let cityB = appModel.partner.homeCity else {
            return CLLocationCoordinate2D(latitude: 10, longitude: -30)
        }
        let lat1 = cityA.latitude * .pi / 180, lon1 = cityA.longitude * .pi / 180
        let lat2 = cityB.latitude * .pi / 180, lon2 = cityB.longitude * .pi / 180

        let x = (cos(lat1) * cos(lon1) + cos(lat2) * cos(lon2)) / 2
        let y = (cos(lat1) * sin(lon1) + cos(lat2) * sin(lon2)) / 2
        let z = (sin(lat1) + sin(lat2)) / 2

        let longitude = atan2(y, x)
        let latitude = atan2(z, sqrt(x * x + y * y))
        return CLLocationCoordinate2D(latitude: latitude * 180 / .pi, longitude: longitude * 180 / .pi)
    }
}

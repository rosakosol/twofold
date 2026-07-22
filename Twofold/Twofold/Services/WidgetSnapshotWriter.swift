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
                    myCity: nil,
                    partnerCity: nil,
                    partnerTimeZoneIdentifier: nil,
                    distanceLabel: nil,
                    anniversaryDate: nil,
                    subscriptionTier: appModel.subscriptionTier,
                    nextFlight: nil,
                    nextReunion: nil,
                    latestMemory: nil,
                    partnerWeather: nil,
                    relationshipStats: nil,
                    coupleID: nil,
                    partnerID: nil,
                    writtenAt: .now
                )
            )
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        let myCity = appModel.currentUser.homeCity
        let partnerCity = appModel.partner.homeCity

        var distanceLabel: String?
        if let mine = myCity?.coordinate, let theirs = partnerCity?.coordinate {
            distanceLabel = MeasurementPreference.distanceLabel(km: Geo.distanceKm(mine, theirs))
        }

        var reunionInfo: WidgetSnapshot.ReunionInfo?
        if let trip = appModel.upcomingTrips.first {
            reunionInfo = WidgetSnapshot.ReunionInfo(
                departureDate: trip.departureDate,
                destinationCity: trip.destination.displayCity,
                isReunionTrip: trip.isReunionTrip
            )
        }

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
                originCode: flight.origin.displayCode,
                destinationCode: flight.destination.displayCode,
                bestDeparture: flight.bestDeparture,
                bestArrival: flight.bestArrival,
                delaySeconds: hasDeparted ? flight.arrivalDelaySeconds : flight.departureDelaySeconds,
                flightNumber: flight.displayNumber,
                progress: flight.progress,
                travelerIsMe: flight.travelerIDs.isEmpty ? nil : flight.travelerIDs.contains(appModel.currentUser.id)
            )
            if let logoURL = flight.displayLogoURL, let data = try? await URLSession.shared.data(from: logoURL).0 {
                WidgetImageCache.writeAirlineLogoImage(data)
            }
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

        // Cached against the previously-written snapshot rather than re-fetched every time —
        // this whole function reruns on every realtime `flights` row change, which can fire
        // every 1-2 minutes for hours while a flight is actively tracked (see
        // refresh-due-flights' polling cadence), fanning out into a WeatherKit call per tick per
        // partner device for a number that hasn't meaningfully changed. Same ~hourly cadence
        // HomeView's own city-gated weather refresh already uses, just keyed off the snapshot's
        // own `writtenAt` instead of in-memory `@State` (this is a stateless enum, not a view).
        var weatherInfo: WidgetSnapshot.WeatherInfo?
        if let partnerCity {
            let previous = WidgetSnapshot.read()
            let cityUnchanged = previous?.partnerCity == partnerCity.displayCity
            let stillFresh = previous.map { Date.now.timeIntervalSince($0.writtenAt) < 3600 } ?? false
            if cityUnchanged, stillFresh, let cached = previous?.partnerWeather {
                weatherInfo = cached
            } else if let reading = await TwofoldWeatherService.currentWeather(for: partnerCity) {
                weatherInfo = WidgetSnapshot.WeatherInfo(symbolName: reading.symbolName, temperatureC: reading.temperatureC)
            }
        }

        let relationshipStats = WidgetSnapshot.RelationshipStats(
            memoryCount: appModel.memories.count,
            tripCount: appModel.trips.count
        )

        WidgetSnapshot.write(
            WidgetSnapshot(
                myID: appModel.currentUser.id,
                myName: appModel.currentUser.name,
                partnerName: appModel.partner.name,
                myCity: myCity?.displayCity,
                partnerCity: partnerCity?.displayCity,
                partnerTimeZoneIdentifier: partnerCity?.timeZoneIdentifier,
                distanceLabel: distanceLabel,
                anniversaryDate: appModel.couple.startedDatingOn,
                subscriptionTier: appModel.subscriptionTier,
                nextFlight: flightInfo,
                nextReunion: reunionInfo,
                latestMemory: memoryInfo,
                partnerWeather: weatherInfo,
                relationshipStats: relationshipStats,
                coupleID: appModel.couple.id,
                partnerID: appModel.partner.id,
                writtenAt: .now
            )
        )
        WidgetCenter.shared.reloadAllTimelines()
    }
}

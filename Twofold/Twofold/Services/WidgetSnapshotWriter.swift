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
                    partnerCity: nil,
                    partnerTimeZoneIdentifier: nil,
                    anniversaryDate: nil,
                    subscriptionTier: appModel.subscriptionTier,
                    nextFlight: nil,
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

        var weatherInfo: WidgetSnapshot.WeatherInfo?
        if let partnerCity, let reading = await TwofoldWeatherService.currentWeather(for: partnerCity) {
            weatherInfo = WidgetSnapshot.WeatherInfo(symbolName: reading.symbolName, temperatureC: reading.temperatureC)
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
                partnerCity: partnerCity?.displayCity,
                partnerTimeZoneIdentifier: partnerCity?.timeZoneIdentifier,
                anniversaryDate: appModel.couple.startedDatingOn,
                subscriptionTier: appModel.subscriptionTier,
                nextFlight: flightInfo,
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

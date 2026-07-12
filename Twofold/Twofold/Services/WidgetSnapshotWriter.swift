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
                    partnerName: appModel.partner.name,
                    partnerCity: nil,
                    partnerTimeZoneIdentifier: nil,
                    anniversaryDate: nil,
                    isSubscriptionActive: appModel.isSubscriptionActive,
                    nextFlight: nil,
                    latestMemory: nil,
                    partnerWeather: nil,
                    coupleID: nil,
                    partnerID: nil,
                    writtenAt: .now
                )
            )
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        let partnerCity = appModel.partner.homeCity

        var flightInfo: WidgetSnapshot.FlightInfo?
        if let flight = appModel.activeOrUpcomingFlight {
            flightInfo = WidgetSnapshot.FlightInfo(
                status: flight.status.rawValue,
                originCity: flight.origin.displayName,
                destinationCity: flight.destination.displayName,
                bestDeparture: flight.bestDeparture,
                bestArrival: flight.bestArrival
            )
        }

        var memoryInfo: WidgetSnapshot.MemoryInfo?
        if let latestMemory = appModel.memories.max(by: { $0.date < $1.date }) {
            memoryInfo = WidgetSnapshot.MemoryInfo(title: latestMemory.title, date: latestMemory.date)
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

        WidgetSnapshot.write(
            WidgetSnapshot(
                partnerName: appModel.partner.name,
                partnerCity: partnerCity?.city,
                partnerTimeZoneIdentifier: partnerCity?.timeZoneIdentifier,
                anniversaryDate: appModel.couple.startedDatingOn,
                isSubscriptionActive: appModel.isSubscriptionActive,
                nextFlight: flightInfo,
                latestMemory: memoryInfo,
                partnerWeather: weatherInfo,
                coupleID: appModel.couple.id,
                partnerID: appModel.partner.id,
                writtenAt: .now
            )
        )
        WidgetCenter.shared.reloadAllTimelines()
    }
}

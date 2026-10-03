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
    ///
    /// Writes twice, deliberately. Everything a widget most needs — names, cities, distance,
    /// flights, subscription tier, stats — is already in memory and needs no network at all. It
    /// used to be written only at the very end, behind six serial network round trips: two avatar
    /// downloads, two signed-URL calls, an airline logo, a memory photo and a WeatherKit read. If
    /// any of those was slow, or the app was backgrounded partway through (which is exactly what
    /// happens when someone opens the app, looks at it, and swipes away to look at their Home
    /// Screen), the `Task` running this went away and the snapshot was never written at all.
    /// Everything before the write had already landed, so the container held cached avatar images
    /// and no snapshot — the state found on a device whose widgets were all blank.
    ///
    /// So the local payload is written and the timelines reloaded immediately; the network work
    /// then enriches it and writes again. A cancellation now costs freshness on the images and the
    /// temperature, not the entire snapshot.
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
                    mySignedDrawingPadURL: nil,
                    partnerSignedDrawingPadURL: nil,
                    writtenAt: .now
                )
            )
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        let myCity = appModel.currentUser.homeCity
        let partnerCity = appModel.partner.homeCity

        // Mirrors `PersonalizedInsightView.sameCity`'s own check — city + country match, not
        // just near-zero distance (two suburbs of the same city shouldn't misfire this, and a
        // coordinate-only check would).
        let isSameCity = myCity != nil && myCity?.city == partnerCity?.city && myCity?.country == partnerCity?.country

        var distanceLabel: String?
        if let mine = myCity?.coordinate, let theirs = partnerCity?.coordinate, !isSameCity {
            distanceLabel = MeasurementPreference.distanceLabel(km: Geo.distanceKm(mine, theirs))
        }

        let upcomingTrips = appModel.upcomingTrips.map { trip in
            WidgetSnapshot.ReunionInfo(
                id: trip.id,
                departureDate: trip.departureDate,
                destinationCity: trip.destination.displayCity,
                isReunionTrip: trip.category == .reunion,
                untilPhrase: Self.untilPhrase(for: trip, appModel: appModel)
            )
        }
        let reunionInfo = upcomingTrips.first

        let flightInfo = appModel.activeOrUpcomingFlight.map { Self.flightInfo(for: $0, currentUserID: appModel.currentUser.id) }
        let trackedFlights = appModel.activeOrUpcomingFlights.map { Self.flightInfo(for: $0, currentUserID: appModel.currentUser.id) }

        let latestMemory = appModel.memories.max(by: { $0.date < $1.date })
        let memoryInfo = latestMemory.map { WidgetSnapshot.MemoryInfo(id: $0.id, title: $0.title, date: $0.date, city: $0.place?.displayCity) }

        let relationshipStats = WidgetSnapshot.RelationshipStats(
            memoryCount: appModel.memories.count,
            tripCount: appModel.trips.count,
            reunionCount: appModel.trips.filter { $0.category == .reunion }.count
        )

        // Without the partner's answer; that is a network read, added below once both have answered.
        let dailyQuestion = appModel.todaysDailyQuestionText.map {
            WidgetSnapshot.DailyQuestionInfo(
                question: $0,
                myAnswered: appModel.todaysMyAnswered,
                partnerAnswered: appModel.todaysPartnerAnswered,
                partnerAnswer: nil
            )
        }

        // Carried over rather than dropped: these three are the only network-derived fields, and
        // the first write happens before the network work that produces them. Blanking them here
        // would black out the drawing-pad and weather widgets for the duration of that work — and
        // permanently, if it never finishes.
        let previous = WidgetSnapshot.read()

        func snapshot(
            weather: WidgetSnapshot.WeatherInfo?,
            mySignedDrawingPadURL: URL?,
            partnerSignedDrawingPadURL: URL?,
            dailyQuestion: WidgetSnapshot.DailyQuestionInfo?
        ) -> WidgetSnapshot {
            WidgetSnapshot(
                myID: appModel.currentUser.id,
                myName: appModel.currentUser.name,
                partnerName: appModel.partner.name,
                myCity: myCity?.displayCity,
                partnerCity: partnerCity?.displayCity,
                partnerTimeZoneIdentifier: partnerCity?.timeZoneIdentifier,
                distanceLabel: distanceLabel,
                isSameCity: isSameCity,
                anniversaryDate: appModel.couple.startedDatingOn,
                subscriptionTier: appModel.subscriptionTier,
                nextFlight: flightInfo,
                trackedFlights: trackedFlights,
                nextReunion: reunionInfo,
                upcomingTrips: upcomingTrips,
                latestMemory: memoryInfo,
                partnerWeather: weather,
                relationshipStats: relationshipStats,
                dailyQuestion: dailyQuestion,
                coupleID: appModel.couple.id,
                partnerID: appModel.partner.id,
                mySignedDrawingPadURL: mySignedDrawingPadURL,
                partnerSignedDrawingPadURL: partnerSignedDrawingPadURL,
                writtenAt: .now
            )
        }

        WidgetSnapshot.write(
            snapshot(
                weather: previous?.partnerWeather,
                mySignedDrawingPadURL: previous?.mySignedDrawingPadURL,
                partnerSignedDrawingPadURL: previous?.partnerSignedDrawingPadURL,
                // The previous partner answer survives the first write only if it is still today's
                // question; a new day's question must not show yesterday's answer.
                dailyQuestion: dailyQuestion.map { info in
                    var info = info
                    if previous?.dailyQuestion?.question == info.question { info.partnerAnswer = previous?.dailyQuestion?.partnerAnswer }
                    return info
                }
            )
        )
        WidgetCenter.shared.reloadAllTimelines()

        // ---- Everything past here is network work. A cancellation from here on leaves the
        // ---- snapshot above in place, which is the whole point of writing it first.

        if let avatarURL = appModel.currentUser.avatarURL, let data = try? await URLSession.shared.data(from: avatarURL).0 {
            WidgetImageCache.writeMyAvatarImage(data)
        }
        if let avatarURL = appModel.partner.avatarURL, let data = try? await URLSession.shared.data(from: avatarURL).0 {
            WidgetImageCache.writePartnerAvatarImage(data)
        }

        if let flight = appModel.activeOrUpcomingFlight,
           let logoURL = flight.displayLogoURL,
           let data = try? await URLSession.shared.data(from: logoURL).0 {
            WidgetImageCache.writeAirlineLogoImage(data)
        }

        if let latestMemory, let photoURL = latestMemory.photoURL, let data = try? await URLSession.shared.data(from: photoURL).0 {
            WidgetImageCache.writeLatestMemoryImage(data)
        } else if latestMemory == nil {
            WidgetImageCache.clearLatestMemoryImage()
        }

        // `drawing-pads` is a private bucket — DrawingPadWidget still fetches these live itself
        // (see WidgetSnapshot's doc comment), so what it needs cached here is a signed URL, not
        // the bytes themselves.
        let mySignedDrawingPadURL = (try? await BackendService.drawingPadSignedURL(
            coupleID: appModel.couple.id, personID: appModel.currentUser.id
        )) ?? previous?.mySignedDrawingPadURL
        let partnerSignedDrawingPadURL = (try? await BackendService.drawingPadSignedURL(
            coupleID: appModel.couple.id, personID: appModel.partner.id
        )) ?? previous?.partnerSignedDrawingPadURL

        // Cached against the previously-written snapshot rather than re-fetched every time —
        // this whole function reruns on every realtime `flights` row change, which can fire
        // every 1-2 minutes for hours while a flight is actively tracked (see
        // refresh-due-flights' polling cadence), fanning out into a WeatherKit call per tick per
        // partner device for a number that hasn't meaningfully changed. Same ~hourly cadence
        // HomeView's own city-gated weather refresh already uses, just keyed off the snapshot's
        // own `writtenAt` instead of in-memory `@State` (this is a stateless enum, not a view).
        var weatherInfo: WidgetSnapshot.WeatherInfo?
        if let partnerCity {
            let cityUnchanged = previous?.partnerCity == partnerCity.displayCity
            let stillFresh = previous.map { Date.now.timeIntervalSince($0.writtenAt) < 3600 } ?? false
            if cityUnchanged, stillFresh, let cached = previous?.partnerWeather {
                weatherInfo = cached
            } else if let reading = await TwofoldWeatherService.currentWeather(for: partnerCity) {
                weatherInfo = WidgetSnapshot.WeatherInfo(symbolName: reading.symbolName, temperatureC: reading.temperatureC, isDaylight: reading.isDaylight)
            } else {
                weatherInfo = previous?.partnerWeather
            }
        }

        // The partner's answer, only once you have both answered (and so only once the database
        // will return it at all).
        var dailyQuestionWithAnswer = dailyQuestion
        if let sessionID = appModel.todaysDailySessionID, appModel.todaysMyAnswered, appModel.todaysPartnerAnswered {
            dailyQuestionWithAnswer?.partnerAnswer = try? await BackendService.fetchPartnerDailyAnswer(
                sessionID: sessionID, partnerID: appModel.partner.id
            )
        }

        WidgetSnapshot.write(
            snapshot(
                weather: weatherInfo,
                mySignedDrawingPadURL: mySignedDrawingPadURL,
                partnerSignedDrawingPadURL: partnerSignedDrawingPadURL,
                dailyQuestion: dailyQuestionWithAnswer
            )
        )
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Who is arriving where, for the Trip countdown widget: the one person travelling by name, or
    /// "you're together" when it is both of you or nobody is set.
    private static func untilPhrase(for trip: Trip, appModel: AppModel) -> String {
        let city = trip.destination.displayCity
        let travellers = Set(trip.travelerIDs)
        if travellers == [appModel.partner.id] { return "until \(appModel.partner.name) lands in \(city)" }
        if travellers == [appModel.currentUser.id] { return "until you land in \(city)" }
        return "until you're together in \(city)"
    }

    private static func flightInfo(for flight: Flight, currentUserID: UUID) -> WidgetSnapshot.FlightInfo {
        let hasDeparted = (flight.bestDeparture ?? .distantFuture) <= .now
        return WidgetSnapshot.FlightInfo(
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
            travelerIsMe: flight.travelerIDs.isEmpty ? nil : flight.travelerIDs.contains(currentUserID),
            originGate: flight.gateOrigin,
            originTerminal: flight.terminalOrigin
        )
    }
}

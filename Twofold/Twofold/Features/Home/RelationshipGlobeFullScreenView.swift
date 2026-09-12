//
//  RelationshipGlobeFullScreenView.swift
//  Twofold
//
//  The globe with the whole screen to itself.
//
//  Inside the distance card it is a 260pt preview that can't really be turned: the card lives in
//  Home's `ScrollView`, and a live MapKit `Map` in a scroll view fights it for every drag — you
//  either nudge the globe or scroll the feed, and which one you got was mostly luck. So the card's
//  globe no longer takes gestures at all, and this is where turning it happens instead.
//
//  Chrome is drawn as overlays over a full-bleed map rather than as a navigation bar. A bar with a
//  scroll-edge appearance goes transparent over the map, which leaves "Close" as dark text on
//  whatever part of the earth happens to be under it — the material-backed control below is the
//  same thing every full-screen map does, and is readable over ocean, cloud and night side alike.
//

import MapKit
import PostHog
import SwiftUI

struct RelationshipGlobeFullScreenView: View {
    let couple: Couple
    let myCity: Place
    let partnerCity: Place
    var activeTrip: Trip?
    let distanceKm: Double

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            RelationshipGlobeView(
                couple: couple,
                partnerACity: myCity,
                partnerBCity: partnerCity,
                activeTrip: activeTrip
            )
            .ignoresSafeArea()
        }
        .overlay(alignment: .topLeading) { closeButton }
        .overlay(alignment: .bottom) { distanceCaption }
        .postHogScreenView("Home: Globe Full Screen")
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .padding(Theme.Spacing.sm)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .padding(Theme.Spacing.md)
    }

    /// The number that was on the card, kept on screen — this view is opened *from* "Distance
    /// between you", and dropping the distance the moment you look closer at it would be an odd
    /// thing to do. Sits at the bottom so it never covers the pins, which are framed centrally.
    private var distanceCaption: some View {
        VStack(spacing: 2) {
            Text("DISTANCE BETWEEN YOU")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.subtleInk)
            Text(MeasurementPreference.distanceLabel(km: distanceKm))
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, Theme.Spacing.lg)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    RelationshipGlobeFullScreenView(
        couple: MockData.couple,
        myCity: MockData.couple.partnerA.homeCity!,
        partnerCity: MockData.couple.partnerB.homeCity!,
        activeTrip: nil,
        distanceKm: 16_800
    )
}

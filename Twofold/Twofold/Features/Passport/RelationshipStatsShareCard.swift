//
//  RelationshipStatsShareCard.swift
//  Twofold
//
//  The relationship's own shareable "our story" card — genuinely unique per couple, since the
//  background gradient comes from whichever country mattered most to this couple (their longest
//  trip's destination, or their most-visited country if ties/no long trip exists yet) and the
//  map at its center is a real flat snapshot of both home cities plus every mappable memory,
//  pinned at the place it actually happened. Two couples with different travel histories get two
//  genuinely different-looking cards, not just different numbers dropped into the same template.
//

import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct RelationshipStatsShareCard: View {
    let couple: Couple
    let trips: [Trip]
    let memories: [Memory]
    let stats: RelationshipMilestoneStats
    /// Pre-rendered by the caller (`RelationshipStatsShareView`, via `MKMapSnapshotter`) — same
    /// reason as `DistanceShareCard.mapSnapshot`: a network-backed snapshot can't be generated
    /// synchronously inside `body`, and `ImageRenderer` can't rasterize a live MapKit `Map` that
    /// was never actually placed in a window. `nil` while loading, or when either partner hasn't
    /// set a home city yet (in which case `mapAndRoute` doesn't render at all).
    var mapSnapshot: MKMapSnapshotter.Snapshot? = nil

    static let canvasSize = CGSize(width: 340, height: 300)

    /// Recent memories that actually have both a photo and a place — the ones eligible to show
    /// as markers on the map. A couple early in their memory-logging habit just gets fewer pins,
    /// never a fabricated one.
    private var mappableMemories: [Memory] {
        Array(
            memories
                .filter { $0.photoURL != nil && $0.place != nil }
                .sorted { $0.date > $1.date }
                .prefix(3)
        )
    }

    /// The trip whose destination gives the card its color identity — the longest trip, since
    /// that's usually the one that meant the most, falling back to whichever country shows up
    /// most across every trip when there's no meaningful "longest" one yet (e.g. only short
    /// weekend trips so far).
    private var accentCountry: String? {
        if let longest = stats.longestTrip { return longest.destination.country }
        return FlightStats(trips: trips, couple: couple).countries.first?.name
    }

    private var accentDestinationLabel: String? {
        stats.longestTrip?.destination.displayCity
    }

    private var gradientColors: [Color] { CountryAccentPalette.gradientColors(for: accentCountry) }

    /// Every country entry in `CountryAccentPalette` is fixed, code-defined hex — safe to
    /// resolve via `UIColor` once, unlike an adaptive/system color. Text and dots below are
    /// fixed white, so a light-flag country (near-white stops like Canada/Switzerland/Peru)
    /// would otherwise render as white-on-white; this flips them to ink instead of trying to
    /// keep every curated palette itself dark enough to hold white.
    private var isLightBackground: Bool {
        let luminances = gradientColors.map { color -> Double in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            return 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
        }
        return (luminances.reduce(0, +) / Double(luminances.count)) > 0.6
    }

    private var textColor: Color { isLightBackground ? Theme.ink : .white }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            TwofoldBrandMark(color: textColor, size: 28, textStyle: .title3)

            coupleAvatars

            VStack(spacing: 4) {
                Text("OUR STORY SO FAR")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(textColor.opacity(0.7))
                Text("\(stats.daysTogether)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(textColor)
                Text("days together")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(textColor.opacity(0.85))
            }

            mapAndRoute
                .padding(.horizontal, -Theme.Spacing.lg)

            HStack(spacing: Theme.Spacing.lg) {
                chip(value: "\(stats.tripCount)", label: "Trips")
                chip(value: "\(stats.reunionCount)", label: "Reunions")
                chip(value: "\(stats.memoryCount)", label: "Memories")
            }

            if let accentDestinationLabel {
                Text("Farthest reach: \(accentDestinationLabel)")
                    .font(.caption)
                    .foregroundStyle(textColor.opacity(0.75))
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(backgroundGradient)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    /// Plain circular avatars — the "who this story belongs to" header, unmoored from any
    /// specific location now that memory photos moved onto the map itself as markers.
    private var coupleAvatars: some View {
        HStack(spacing: Theme.Spacing.md) {
            AvatarView(person: couple.partnerA, size: 56, showsRing: true)
            AvatarView(person: couple.partnerB, size: 56, showsRing: true)
        }
    }

    private var backgroundGradient: some View {
        ZStack {
            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.white.opacity(0.18), .clear], center: .center, startRadius: 10, endRadius: 260)
        }
    }

    private var userCoordinate: CLLocationCoordinate2D? { couple.partnerA.homeCity?.coordinate }
    private var partnerCoordinate: CLLocationCoordinate2D? { couple.partnerB.homeCity?.coordinate }

    /// A real flat map (`MKMapSnapshotter`, same mechanism `DistanceShareCard` uses) framed to
    /// fit both home cities and every mappable memory, with a solid route between the cities and
    /// each memory's own photo pinned at the place it actually happened. Doesn't render at all
    /// when either partner hasn't set a home city — never a fabricated pin pair. Fills what used
    /// to be a mostly-empty canvas for any couple without a long trip history yet, and works
    /// regardless of trip count since it's about where they *live*, not where they've been.
    @ViewBuilder
    private var mapAndRoute: some View {
        if let userCoordinate, let partnerCoordinate {
            ZStack {
                if let mapSnapshot {
                    Image(uiImage: mapSnapshot.image)
                        .resizable()

                    // Many short chords between closely-spaced great-circle samples — the same
                    // technique `DistanceShareCard` uses — so the drawn line follows the true
                    // geodesic arc rather than cutting a straight chord across the map image.
                    Path { path in
                        let sampleCount = 40
                        let samples = (0...sampleCount).map { i in
                            Geo.intermediateGreatCirclePoint(userCoordinate, partnerCoordinate, fraction: Double(i) / Double(sampleCount))
                        }
                        guard let first = samples.first else { return }
                        path.move(to: mapSnapshot.point(for: first))
                        for coordinate in samples.dropFirst() {
                            path.addLine(to: mapSnapshot.point(for: coordinate))
                        }
                    }
                    .stroke(Color(hex: "3D8FF5"), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                    ForEach(mappableMemories) { memory in
                        if let place = memory.place, let photoURL = memory.photoURL {
                            memoryMarker(at: mapSnapshot.point(for: place.coordinate), photoURL: photoURL)
                        }
                    }

                    cityPin(at: mapSnapshot.point(for: userCoordinate), label: couple.partnerA.homeCity?.displayCity)
                    cityPin(at: mapSnapshot.point(for: partnerCoordinate), label: couple.partnerB.homeCity?.displayCity)
                } else {
                    Color(hex: "0B2340")
                    ProgressView().tint(.white)
                }
            }
            .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1) }
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        }
    }

    private func cityPin(at point: CGPoint, label: String?) -> some View {
        Group {
            ZStack {
                Circle().fill(.white.opacity(0.3)).frame(width: 20, height: 20)
                Circle().fill(.white).frame(width: 10, height: 10)
                Circle().fill(Color(hex: "FFD166")).frame(width: 6, height: 6)
            }
            .position(point)

            if let label {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: Capsule())
                    .fixedSize()
                    .position(x: point.x, y: point.y + 16)
            }
        }
    }

    /// A small circular photo, not a plain dot — a memory location is the one kind of marker
    /// where showing the actual moment (rather than an abstract pin) is worth the extra weight.
    private func memoryMarker(at point: CGPoint, photoURL: URL) -> some View {
        AsyncImage(url: photoURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Theme.skyBlue, Theme.leafGreen], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "photo.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        .position(point)
    }

    private func chip(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(textColor)
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(textColor.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    RelationshipStatsShareCard(
        couple: MockData.couple,
        trips: MockData.trips,
        memories: MockData.memories,
        stats: RelationshipMilestoneStats(trips: MockData.trips, memories: MockData.memories, startedDatingOn: .now.addingTimeInterval(-86_400 * 400))
    )
    .padding()
    .background(Color.black)
}

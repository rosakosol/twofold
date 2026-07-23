//
//  RelationshipStatsShareCard.swift
//  Twofold
//
//  The relationship's own shareable "our story" card — the photo grid at its center is real
//  memory photos, in the order they actually happened, each in the same white-bordered "polaroid"
//  treatment `MemoryDetailView` uses for its own photo card. Background defaults to a warm sunset
//  gradient (`RelationshipStatsCardBackground.auto`), with a few curated alternatives the user
//  can pick instead via `RelationshipStatsCustomizationView`.
//

import SwiftUI
import UIKit

struct RelationshipStatsShareCard: View {
    let couple: Couple
    let trips: [Trip]
    let memories: [Memory]
    /// Which of `memories` to actually show, chosen by the caller (`RelationshipStatsShareView`)
    /// — either its own random default or the user's explicit picks — rather than this view
    /// silently picking its own "most recent" subset. Always rendered chronologically regardless
    /// of the order IDs were selected in.
    let selectedMemoryIDs: Set<Memory.ID>
    let stats: RelationshipMilestoneStats
    var backgroundTheme: RelationshipStatsCardBackground = .auto
    var showTripsChip = true
    var showReunionsChip = true
    var showMemoriesChip = true

    /// Maximum photos this card ever shows — matches the cap `RelationshipStatsShareView`'s
    /// selection UI enforces, kept here too as a last line of defense against a card that grows
    /// past a single shareable screen.
    static let maxStoryPhotos = 6

    /// Alternating tilt per photo, same scrapbook idea as `MemoryDetailView`'s single `-2°`
    /// photo card, just varied per item so a grid of them doesn't look stamped from one mold.
    /// Fixed (not random) so re-renders — including the offscreen one `ShareLink` triggers —
    /// always produce the same image.
    private static let photoRotations: [Double] = [-4, 3, -3, 4, -2, 3]

    /// The selected memories, oldest first — a chronological "story" regardless of selection
    /// order (random default or manual picks).
    private var storyMemories: [Memory] {
        Array(
            memories
                .filter { selectedMemoryIDs.contains($0.id) }
                .sorted { $0.date < $1.date }
                .prefix(Self.maxStoryPhotos)
        )
    }

    private var gradientColors: [Color] { backgroundTheme.colors }

    /// Every `RelationshipStatsCardBackground` case is a fixed, code-defined hex — safe to
    /// resolve via `UIColor` once, unlike an adaptive/system color. Text and dots below are
    /// fixed white, so a light background would otherwise render as white-on-white; this flips
    /// them to ink instead of trying to keep every curated option itself dark enough to hold white.
    private var isLightBackground: Bool {
        let luminances = gradientColors.map { color -> Double in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            return 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
        }
        return (luminances.reduce(0, +) / Double(luminances.count)) > 0.6
    }

    private var textColor: Color { isLightBackground ? Theme.ink : .white }

    @ViewBuilder
    var body: some View {
        if backgroundTheme == .classic {
            classicBody
        } else {
            storyBody
        }
    }

    private var storyBody: some View {
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

            storySection

            if showTripsChip || showReunionsChip || showMemoriesChip {
                HStack(spacing: Theme.Spacing.lg) {
                    if showTripsChip { chip(value: "\(stats.tripCount)", label: "Trips") }
                    if showReunionsChip { chip(value: "\(stats.reunionCount)", label: "Reunions") }
                    if showMemoriesChip { chip(value: "\(stats.memoryCount)", label: "Memories") }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(backgroundGradient)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    /// The default — a white card that mirrors the in-app `RelationshipStatsCard` almost exactly
    /// (same couple header, hero row, and milestone tiles with matching icons), rather than the
    /// photo-story/gradient treatment every other background option uses. Reuses
    /// `RelationshipStatsCard` directly instead of re-implementing its layout — this view exists
    /// only to add the brand mark on top, which the in-app card (surrounded by its own screen
    /// chrome) has no need for.
    private var classicBody: some View {
        VStack(spacing: Theme.Spacing.sm) {
            TwofoldBrandMark(color: Theme.ink, size: 24, textStyle: .title3)
            RelationshipStatsCard(
                couple: couple,
                stats: stats,
                showTripsStat: showTripsChip,
                showReunionsStat: showReunionsChip,
                showMemoriesStat: showMemoriesChip
            )
        }
        // `RelationshipStatsCard` already carries its own `SectionCard` padding — this only
        // needs enough outer margin for the brand mark and the rounded-corner clip below, not a
        // second full padding pass stacked on top of that (which was making the card's own
        // bottom-half stats look over-padded specifically on this share screen, not in-app).
        .padding(Theme.Spacing.sm)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    /// Plain circular avatars — the "who this story belongs to" header.
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

    /// Real memory photos when there are any; otherwise, if both partners have a home city set,
    /// a curvy path and the real distance between them — never both empty and never a
    /// placeholder grid of empty tiles.
    @ViewBuilder
    private var storySection: some View {
        if !storyMemories.isEmpty {
            memoryPhotoGrid
        } else {
            curvyDistancePath
        }
    }

    /// Real memory photos in chronological rows, each in `MemoryDetailView`'s own white-bordered,
    /// drop-shadowed, gently-rotated "polaroid" treatment.
    private var memoryPhotoGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
            ForEach(Array(storyMemories.enumerated()), id: \.element.id) { index, memory in
                memoryPolaroid(memory, rotation: Self.photoRotations[index % Self.photoRotations.count])
            }
        }
        .padding(.top, Theme.Spacing.xs)
    }

    private func memoryPolaroid(_ memory: Memory, rotation: Double) -> some View {
        MemoryPhotoView(memory: memory, cornerRadius: 8)
            .frame(width: 88, height: 88)
            .padding(5)
            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            .rotationEffect(.degrees(rotation))
    }

    /// The "no photographed memories yet" fallback — a hand-drawn (not a map) curve between the
    /// two of you, with the real distance underneath. Doesn't render at all if either partner
    /// hasn't set a home city — never a fabricated pair of cities.
    @ViewBuilder
    private var curvyDistancePath: some View {
        if let userCity = couple.partnerA.homeCity, let partnerCity = couple.partnerB.homeCity {
            VStack(spacing: Theme.Spacing.sm) {
                VStack(spacing: 2) {
                    Canvas { context, size in
                        let leftAnchor = CGPoint(x: 30, y: size.height / 2)
                        let rightAnchor = CGPoint(x: size.width - 30, y: size.height / 2)
                        var path = Path()
                        path.move(to: leftAnchor)
                        path.addCurve(
                            to: rightAnchor,
                            control1: CGPoint(x: size.width * 0.38, y: 4),
                            control2: CGPoint(x: size.width * 0.62, y: size.height - 4)
                        )
                        context.stroke(path, with: .color(textColor.opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 7]))

                        for point in [leftAnchor, rightAnchor] {
                            context.fill(Path(ellipseIn: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18)), with: .color(textColor.opacity(0.18)))
                            context.fill(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)), with: .color(Color(hex: "FFD166")))
                        }
                    }
                    .frame(height: 44)

                    HStack {
                        Text(userCity.displayCity)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(textColor.opacity(0.85))
                        Spacer()
                        Text(partnerCity.displayCity)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(textColor.opacity(0.85))
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                }

                Text("\(MeasurementPreference.distanceLabel(km: Geo.distanceKm(userCity.coordinate, partnerCity.coordinate))) apart")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(textColor)
            }
            .padding(.top, Theme.Spacing.xs)
        }
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
        selectedMemoryIDs: Set(MockData.memories.prefix(6).map(\.id)),
        stats: RelationshipMilestoneStats(couple: MockData.couple, trips: MockData.trips, memories: MockData.memories)
    )
    .padding()
    .background(Color.black)
}

//
//  DistanceSnapshotCard.swift
//  Twofold
//
//  Pure-SwiftUI rendering of the distance-reveal moment — avatars joined by a dashed path with a
//  heart, the rolling distance number, a real-world comparison, and both city names — extracted
//  out of `PersonalizedInsightView` (where it started as that screen's own `ShareLink` snapshot)
//  so `TwofoldPreviewView`'s own "save your progress" screen can show the exact same card instead
//  of a second, different-looking recap. `ImageRenderer` can't rasterize MapKit views, which is
//  why this re-draws the reveal rather than embedding the live map both screens otherwise use.
//

import SwiftUI

struct DistanceSnapshotCard: View {
    let distanceKm: Double
    let comparison: String
    let myCity: Place
    let partnerCity: Place
    let selfPhoto: UIImage?
    let partnerPhoto: UIImage?

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.sm) {
                avatar(selfPhoto, tint: Theme.skyBlue)

                Line()
                    .stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5]))
                    .frame(height: 2)
                    .overlay {
                        Text("❤️")
                            .font(.title3)
                    }

                avatar(partnerPhoto, tint: Theme.heartRed)
            }

            VStack(spacing: Theme.Spacing.xs) {
                Text("\(MeasurementPreference.distanceLabel(km: distanceKm)) apart")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(comparison)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                Text("\(myCity.displayCity) ↔ \(partnerCity.displayCity)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
            .multilineTextAlignment(.center)

            Text("twofold")
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 340)
        .background(
            LinearGradient(
                colors: [Color(hex: "1E3A5F"), Color(hex: "3E7CA6"), Color(hex: "6FBF8B")],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func avatar(_ photo: UIImage?, tint: Color) -> some View {
        ZStack {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                Circle().fill(tint)
                Image(systemName: "person.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }

    // MARK: - Comparison copy

    /// Well-known country lengths/widths (approximate, in km) to make the number tangible.
    /// Picked by closest ratio so e.g. 6,054 km reads as "about the width of Canada".
    private static let distanceComparisons: [(km: Double, label: String)] = [
        (250, "the length of Wales"),
        (550, "the length of England"),
        (1_000, "the length of France"),
        (1_600, "the length of Sweden"),
        (2_900, "the width of India"),
        (4_000, "the width of Australia"),
        (4_300, "the width of the USA"),
        (5_500, "the width of Canada"),
        (9_000, "the width of Russia"),
        (10_000, "a quarter of the way around the Earth"),
        (20_000, "halfway around the Earth"),
    ]

    static func comparison(for km: Double) -> String {
        guard km >= 150 else { return "Closer than you think ❤️" }
        let nearest = distanceComparisons.min {
            abs(log($0.km / km)) < abs(log($1.km / km))
        }!
        return "That's about \(nearest.label) 🌏"
    }
}

#Preview {
    DistanceSnapshotCard(
        distanceKm: 16_902,
        comparison: DistanceSnapshotCard.comparison(for: 16_902),
        myCity: Place.commonCities.first { $0.city == "Melbourne" }!,
        partnerCity: Place.commonCities.first { $0.city == "London" }!,
        selfPhoto: nil,
        partnerPhoto: nil
    )
    .padding()
    .background(Color.black)
}

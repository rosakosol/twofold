//
//  WorldVisitedMapView.swift
//  Twofold
//
//  Flat 2D "countries you've been to" choropleth — deliberately not a 3D globe (unlike
//  `DistanceShareCard`'s `MKMapSnapshotter`-rendered sphere): a single `Canvas` pass over the
//  bundled `WorldMap.countries` boundaries, filled per country depending on whether it's in
//  `visitedCountryNames`. No network/snapshot dependency, renders identically on-screen and
//  inside `ImageRenderer` share cards.
//

import SwiftUI

struct WorldVisitedMapView: View {
    /// Boundary names (`WorldCountryBoundary.name`, already alias-resolved — see
    /// `WorldMap.visitedNames(from:)`) to fill in as visited.
    let visitedCountryNames: Set<String>
    var visitedColor: Color = Theme.leafGreen
    var unvisitedColor: Color = .white.opacity(0.08)
    var strokeColor: Color = .white.opacity(0.22)

    var body: some View {
        Canvas { context, size in
            for country in WorldMap.countries {
                let path = Self.path(for: country, in: size)
                let isVisited = visitedCountryNames.contains(country.name)
                context.fill(path, with: .color(isVisited ? visitedColor : unvisitedColor), style: FillStyle(eoFill: true))
                context.stroke(path, with: .color(strokeColor), lineWidth: 0.4)
            }
        }
        // The bundled boundary points are normalized to a 0...1 box representing 360° of
        // longitude by 180° of latitude — a plain 2:1 rectangle. Any other aspect would stretch
        // every country horizontally or vertically, so this is enforced here rather than left to
        // whatever frame a caller happens to apply.
        .aspectRatio(2, contentMode: .fit)
    }

    /// Even-odd fill (rather than the default nonzero rule) so holes — an enclave like Lesotho
    /// inside South Africa — punch out correctly regardless of the source data's ring winding
    /// order, which GeoJSON doesn't strictly guarantee.
    private static func path(for country: WorldCountryBoundary, in size: CGSize) -> Path {
        var path = Path()
        for polygon in country.polygons {
            for ring in polygon {
                guard let first = ring.first else { continue }
                path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
                for point in ring.dropFirst() {
                    path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
                }
                path.closeSubpath()
            }
        }
        return path
    }
}

#Preview {
    WorldVisitedMapView(visitedCountryNames: ["Australia", "Singapore", "United Kingdom", "United States of America"])
        .padding()
        .background(Color(hex: "0B111F"))
}

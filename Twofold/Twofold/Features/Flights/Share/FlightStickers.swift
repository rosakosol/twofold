//
//  FlightStickers.swift
//  Twofold
//
//  The six die-cut flight stickers (SHARE_REDESIGN.md §5, references `source/Sticker*B.dc.html`):
//  boarding pass, luggage tag, live flight, distance, arrivals board and passport stamp. Each has
//  a 5pt white edge following its shape and a shadow that traces it, and exports as a transparent
//  PNG with room around it for that shadow.
//
//  The stickers are fixed-size images, so their text is fixed too rather than Dynamic Type.
//

import SwiftUI

struct FlightSticker: View {
    let kind: FlightStickerKind
    let data: FlightStickerData

    var body: some View {
        Group {
            switch kind {
            case .boardingPass: BoardingPassSticker(data: data)
            case .luggageTag: LuggageTagSticker(data: data)
            case .live: LiveFlightSticker(data: data)
            case .distance: DistanceSticker(data: data)
            case .arrivals: ArrivalsSticker(data: data)
            case .stamp: PassportStampSticker(data: data)
            }
        }
        .environment(\.dynamicTypeSize, .large)
    }

    /// The transparent PNG: 3x, with 24pt of clear space so the shadow isn't cut off (§5.1).
    @MainActor
    func renderedImage() -> UIImage? {
        let renderer = ImageRenderer(content: padding(24).environment(\.colorScheme, .light))
        renderer.scale = 3
        renderer.isOpaque = false
        return renderer.uiImage
    }
}

// MARK: - Shared pieces

/// The globe-heart and "twofold" in New York.
private struct StickerBrand: View {
    var size: CGFloat = 11
    var opacity: Double = 0.6
    var color: Color = .white

    var body: some View {
        HStack(spacing: 4) {
            Image("GlobeHeart")
                .resizable()
                .scaledToFit()
                .frame(width: size + 1, height: size)
            Text("twofold")
                .font(.system(size: size, design: .serif))
                .tracking(-0.01 * size)
        }
        .foregroundStyle(color)
        .opacity(opacity)
        .accessibilityHidden(true)
    }
}

/// Decorative stripes: a barcode reads as "boarding pass" faster than any label could.
private struct Barcode: View {
    let ink: Color
    /// Bar and gap widths, repeated.
    let pattern: [CGFloat]

    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 0
            var index = 0
            while x < size.width {
                let width = pattern[index % pattern.count]
                if index.isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: x, y: 0, width: min(width, size.width - x), height: size.height)), with: .color(ink))
                }
                x += width
                index += 1
            }
        }
        .accessibilityHidden(true)
    }
}

private struct StickerLabel: View {
    let title: String
    let value: String
    var valueSize: CGFloat = 16
    var titleColor: Color? = nil
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                // Inherits the sticker's ink unless told otherwise; `.primary` would be black here.
                .foregroundStyle(titleColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.foreground))
            Text(value)
                .font(.system(size: valueSize, weight: .bold))
                .lineLimit(1)
        }
    }
}

private extension View {
    /// The shadow that follows the sticker's alpha, cut-outs included.
    func stickerShadow() -> some View {
        compositingGroup().shadow(color: Theme.Share.stickerShadow, radius: 7, y: 8)
    }
}

// MARK: - Boarding pass (§5.2)

/// A rounded rectangle with a half-circle notch out of the top and bottom edges where the stub
/// begins.
private struct NotchedTicket: Shape {
    var radius: CGFloat = 26
    var notchX: CGFloat = 251
    var notchRadius: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let body = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        var notches = Path()
        notches.addEllipse(in: CGRect(x: notchX - notchRadius, y: rect.minY - notchRadius, width: notchRadius * 2, height: notchRadius * 2))
        notches.addEllipse(in: CGRect(x: notchX - notchRadius, y: rect.maxY - notchRadius, width: notchRadius * 2, height: notchRadius * 2))
        return body.subtracting(notches)
    }
}

private struct BoardingPassSticker: View {
    let data: FlightStickerData

    var body: some View {
        HStack(spacing: 0) {
            main
            stub
        }
        .frame(width: 350, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        .padding(5)
        .background(.white)
        .clipShape(NotchedTicket())
        .frame(width: 360, height: 210)
        .stickerShadow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Boarding pass sticker: \(data.flightNumber) \(data.origin.city) \(data.origin.code) to \(data.destination.city) \(data.destination.code)"))
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Boarding pass")
                Spacer()
                Text(data.flightNumber)
            }
            .font(.system(size: 12, weight: .semibold))

            Spacer(minLength: 0)

            HStack(alignment: .bottom) {
                airport(data.origin, alignment: .leading)
                Spacer(minLength: 4)
                Image(systemName: "airplane")
                    .font(.system(size: 26))
                    .padding(.bottom, 18)
                Spacer(minLength: 4)
                airport(data.destination, alignment: .trailing)
            }

            Spacer(minLength: 0)

            HStack(alignment: .top) {
                StickerLabel(title: String(localized: "Flight time"), value: data.duration ?? "—")
                Spacer()
                if let distance = data.distance {
                    StickerLabel(title: String(localized: "Distance"), value: distance, alignment: .trailing)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 15, trailing: 16))
        .frame(width: 246, height: 200)
        .background {
            ZStack {
                Theme.Share.signature
                BrandHighlight()
            }
        }
    }

    private func airport(_ airport: FlightStickerData.Airport, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(airport.code)
                .font(.system(size: 42, weight: .heavy))
                .tracking(-1.26)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(airport.city)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
    }

    private var stub: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Departs")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Share.paperMuted)
                Text(data.departureDate ?? "—")
                    .font(.system(size: 15, weight: .bold))
                if let time = data.departureTime {
                    Text(time)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            Spacer(minLength: 0)
            if let terminal = data.terminal {
                StickerLabel(title: String(localized: "Terminal"), value: terminal, valueSize: 15, titleColor: Theme.Share.paperMuted)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                Barcode(ink: Theme.Share.paperInk, pattern: [2, 2, 1, 3, 3, 1])
                    .frame(height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                StickerBrand(color: Theme.Share.paperInk)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .foregroundStyle(Theme.Share.paperInk)
        .padding(EdgeInsets(top: 16, leading: 14, bottom: 14, trailing: 12))
        .frame(width: 104, height: 200, alignment: .leading)
        .background(Theme.Share.paper)
        .overlay(alignment: .leading) {
            Path { path in
                path.move(to: CGPoint(x: 1, y: 0))
                path.addLine(to: CGPoint(x: 1, y: 200))
            }
            .stroke(Theme.Share.stubDash, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .frame(width: 2)
        }
    }
}

// MARK: - Luggage tag (§5.3)

/// Chamfered top corners, rounded bottom ones.
private struct TagShape: Shape {
    let chamfer: CGFloat
    let bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + chamfer, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - chamfer, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + chamfer))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY), radius: bottomRadius)
        path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomRadius), radius: bottomRadius)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + chamfer))
        path.closeSubpath()
        return path
    }
}

/// The tag with its punched hole, which goes through everything.
private struct PunchedTag: Shape {
    func path(in rect: CGRect) -> Path {
        let hole = Path(ellipseIn: CGRect(x: rect.midX - 9, y: rect.minY + 21, width: 18, height: 18))
        return TagShape(chamfer: 34, bottomRadius: 22).path(in: rect).subtracting(hole)
    }
}

private struct LuggageTagSticker: View {
    let data: FlightStickerData

    var body: some View {
        ZStack(alignment: .topLeading) {
            tag
                .clipShape(PunchedTag())
                .stickerShadow()
                .offset(x: 10, y: 52)
            string
        }
        .frame(width: 230, height: 380, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Luggage tag sticker: \(data.destination.code) \(data.destination.city), handle with love, flight \(data.flightNumber)"))
    }

    private var tag: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 13))
                Text("Handle with love")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(Theme.Share.signature)

            Text(data.destination.code)
                .font(.system(size: 92, weight: .heavy))
                .tracking(-4.6)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 6)
            Text(data.destination.city)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)

            HStack(alignment: .top) {
                StickerLabel(title: String(localized: "Flight"), value: data.flightNumber, valueSize: 13, titleColor: Theme.Share.paperMuted)
                Spacer(minLength: 8)
                StickerLabel(
                    title: String(localized: "Arrives"),
                    value: [data.arrivalDate, data.arrivalTime].compactMap { $0 }.joined(separator: " · "),
                    valueSize: 13,
                    titleColor: Theme.Share.paperMuted,
                    alignment: .trailing
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Barcode(ink: Theme.Share.paperInk, pattern: [3, 2, 1, 3, 2, 1, 1, 3])
                .frame(width: 164, height: 24)
                .padding(.top, 10)

            StickerBrand(color: Theme.Share.paperInk)
                .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.Share.paperInk)
        .padding(.top, 46)
        .frame(width: 200, height: 310)
        .background(Theme.Share.paper)
        .overlay(alignment: .top) {
            Circle()
                .strokeBorder(Theme.Share.tagRing, lineWidth: 4)
                .frame(width: 28, height: 28)
                .padding(.top, 11)
        }
        .clipShape(TagShape(chamfer: 31, bottomRadius: 18))
        .padding(5)
        .background(.white)
        .frame(width: 210, height: 320)
    }

    /// The loop through the hole: blue over a white edge, as drawn in the reference.
    private var string: some View {
        let loop = Path { path in
            path.move(to: CGPoint(x: 115, y: 87))
            path.addCurve(to: CGPoint(x: 86, y: 18), control1: CGPoint(x: 104, y: 62), control2: CGPoint(x: 74, y: 44))
            path.addCurve(to: CGPoint(x: 140, y: 24), control1: CGPoint(x: 96, y: -2), control2: CGPoint(x: 136, y: 0))
            path.addCurve(to: CGPoint(x: 115, y: 87), control1: CGPoint(x: 144, y: 46), control2: CGPoint(x: 124, y: 64))
        }
        return ZStack {
            loop.stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
            loop.stroke(Theme.Share.tagString, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        }
        .frame(width: 230, height: 100)
        .accessibilityHidden(true)
    }
}

// MARK: - Live flight (§5.4)

private struct LiveFlightSticker: View {
    let data: FlightStickerData

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(person: data.traveller, size: 54)
                .padding(3)
                .background(Theme.Share.signature, in: Circle())

            VStack(alignment: .leading, spacing: 9) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle().frame(width: 7, height: 7)
                            Text("In the air · \(data.flightNumber)")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Share.stampInk)
                        Spacer(minLength: 4)
                        StickerBrand(opacity: 0.55, color: Theme.Share.liveInk)
                    }
                    Text(headline)
                        .font(.system(size: 20, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(Theme.Share.liveInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                HStack(spacing: 8) {
                    Text(data.origin.code)
                    progressBar
                    Text(data.destination.code)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Share.stampInk)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Share.liveMuted)
            }
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 20))
        .frame(width: 360, height: 128)
        .background(.white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .stickerShadow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Flight \(data.flightNumber), \(Int((data.progress * 100).rounded()))% complete, lands in \(data.remainingForVoiceOver)"))
    }

    private var headline: String {
        data.travellerIsMe
            ? String(localized: "I land in \(data.timeRemaining)")
            : String(localized: "\(data.traveller.name) lands in \(data.timeRemaining)")
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let x = geo.size.width * data.progress
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Share.liveTrack)
                Capsule().fill(Theme.Share.signatureHorizontal)
                    .frame(width: max(6, x))
                Image(systemName: "airplane")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Theme.Share.planeMarker, in: Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                    .shadow(color: Theme.Share.stickerShadow.opacity(0.7), radius: 2, y: 1)
                    .position(x: x, y: 3)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Distance (§5.5)

private struct DistanceSticker: View {
    let data: FlightStickerData

    private static let start = CGPoint(x: 12, y: 74)
    private static let control = CGPoint(x: 145, y: -14)
    private static let end = CGPoint(x: 272, y: 70)

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text(data.distance ?? "—")
                    .font(.system(size: 52, weight: .heavy))
                    .tracking(-2.08)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                StickerBrand(size: 12, opacity: 0.75)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                arc
                HStack {
                    Text(data.origin.city)
                    Spacer()
                    Text(data.destination.city)
                }
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(EdgeInsets(top: 20, leading: 20, bottom: 14, trailing: 20))
        .frame(width: 330, height: 220)
        .background {
            ZStack {
                Theme.Share.signature
                BrandHighlight()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
        .padding(5)
        .background(.white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .stickerShadow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Distance sticker: \(data.distance ?? "") from \(data.origin.city) to \(data.destination.city)"))
    }

    private static func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
            y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
        )
    }

    /// The curve's direction at `t`, for turning the plane along it.
    private static func heading(at t: CGFloat) -> Angle {
        let dx = 2 * (1 - t) * (control.x - start.x) + 2 * t * (end.x - control.x)
        let dy = 2 * (1 - t) * (control.y - start.y) + 2 * t * (end.y - control.y)
        return .radians(atan2(dy, dx))
    }

    private var arc: some View {
        let plane = Self.point(at: 0.62)
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: Self.start)
                path.addQuadCurve(to: Self.end, control: Self.control)
            }
            .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [2, 7]))
            Circle().fill(.white)
                .frame(width: 10, height: 10)
                .position(Self.start)
            Image(systemName: "heart.fill")
                .font(.system(size: 18))
                .position(x: Self.end.x, y: Self.end.y - 1)
            // SF's airplane already points right, so it turns by the heading alone.
            Image(systemName: "airplane")
                .font(.system(size: 22))
                .rotationEffect(Self.heading(at: 0.62))
                .position(plane)
        }
        .frame(width: 290, height: 86)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}

// MARK: - Arrivals board (§5.6)

private struct ArrivalsSticker: View {
    let data: FlightStickerData

    private static let rowWidth: CGFloat = 314

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "airplane.arrival")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Arrivals")
                    if let country = data.destination.country {
                        Text("·").accessibilityHidden(true)
                        flagged(data.destination.flag, country)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 6)
                StickerBrand(size: 12, opacity: 0.7)
            }

            Spacer(minLength: 0)
            tiles
            Spacer(minLength: 0)

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text("\(data.flightNumber) from")
                    flagged(data.origin.flag, [data.origin.city, data.arrivalTime].compactMap { $0 }.joined(separator: " · "))
                }
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                statusPill
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(width: 350, height: 180)
        .background {
            ZStack {
                Theme.Share.flightBlue
                BrandHighlight()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .padding(5)
        .background(.white, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .stickerShadow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Arrivals board sticker: \(data.destination.city). \(data.flightNumber) from \(data.origin.city), \(statusText)"))
    }

    /// A flag with a thin white outline, since it sits on blue, then the words.
    private func flagged(_ flag: String?, _ text: String) -> some View {
        HStack(spacing: 5) {
            if let flag {
                Text(flag)
                    .font(.system(size: 14))
                    .shadow(color: .white.opacity(0.7), radius: 0.5)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
    }

    /// The city in capitals, one tile a letter: up to nine at 32pt, smaller tiles for ten to
    /// twelve, and the airport code for anything longer.
    private var letters: [Character] {
        let city = Array(data.destination.city.uppercased())
        return Self.tileWidth(for: city.count) == nil ? Array(data.destination.code.uppercased()) : city
    }

    private static func tileWidth(for count: Int) -> CGFloat? {
        guard count > 0 else { return nil }
        let fitted = (rowWidth - 3 * CGFloat(count - 1)) / CGFloat(count)
        if fitted >= 32 { return 32 }
        return fitted >= 24 ? fitted : nil
    }

    private var tiles: some View {
        let letters = self.letters
        let width = Self.tileWidth(for: letters.count) ?? 32
        return HStack(spacing: 3) {
            ForEach(Array(letters.enumerated()), id: \.offset) { _, letter in
                Text(String(letter))
                    .font(.system(size: 30 * width / 32, weight: .bold, design: .monospaced))
                    .frame(width: width, height: 52)
                    .background {
                        VStack(spacing: 0) {
                            Theme.Share.flapTop
                            Theme.Share.flapBottom
                        }
                    }
                    .overlay {
                        Theme.Share.flapLine.frame(height: 2)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .accessibilityHidden(true)
    }

    private var statusText: String {
        switch data.arrivalStatus {
        case .landed: String(localized: "Landed")
        case .onTime: String(localized: "On time")
        case .delayed(let minutes): String(localized: "Delayed \(minutes) min")
        }
    }

    /// A word and an icon, never colour alone.
    private var statusPill: some View {
        let (icon, ink): (String, Color) = switch data.arrivalStatus {
        case .landed: ("checkmark", Theme.Share.landedText)
        case .onTime: ("clock", Theme.Share.landedText)
        case .delayed: ("exclamationmark.circle", Theme.Share.delayedText)
        }
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .heavy))
            Text(statusText)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(ink)
        .padding(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 10))
        .background(.white, in: Capsule())
    }
}

// MARK: - Passport stamp (§5.7)

/// Text laid along a circle, one glyph at a time, since SwiftUI has no text-on-path.
///
/// Along the top it reads clockwise with the letters standing outward; along the bottom it reads
/// left to right with the letters standing toward the centre. Each glyph is measured with the
/// same font it is drawn in, so the spacing holds for any city name.
private struct CircularText: View {
    let text: String
    let radius: CGFloat
    let size: CGFloat
    var tracking: CGFloat = 1.2
    let onTop: Bool

    var body: some View {
        let font = UIFont.systemFont(ofSize: size, weight: .bold)
        let glyphs = text.map { String($0) }
        let widths = glyphs.map { ($0 as NSString).size(withAttributes: [.font: font]).width + tracking }
        let total = widths.reduce(0, +)
        // The radius the glyphs' centres sit on: the baseline is on `radius`.
        let centreRadius = onTop ? radius + size * 0.35 : radius - size * 0.35

        ZStack {
            ForEach(glyphs.indices, id: \.self) { index in
                let along = widths[..<index].reduce(0, +) + widths[index] / 2 - total / 2
                // Top: centred on 12 o'clock, going clockwise. Bottom: centred on 6, going left to right.
                let angle = onTop ? -CGFloat.pi / 2 + along / centreRadius : CGFloat.pi / 2 - along / centreRadius
                Text(glyphs[index])
                    .font(Font(font))
                    .fixedSize()
                    .rotationEffect(.radians(onTop ? angle + .pi / 2 : angle - .pi / 2))
                    .offset(x: cos(angle) * centreRadius, y: sin(angle) * centreRadius)
            }
        }
    }
}

private struct PassportStampSticker: View {
    let data: FlightStickerData

    var body: some View {
        ZStack {
            Circle().fill(.white).frame(width: 272, height: 272)
            Circle().fill(Theme.Share.paper).frame(width: 260, height: 260)

            ZStack {
                Circle().stroke(lineWidth: 4.5).frame(width: 236, height: 236)
                Circle().stroke(lineWidth: 1.5).frame(width: 212, height: 212)
                Circle().stroke(lineWidth: 1.5).frame(width: 128, height: 128)

                CircularText(text: arcText(String(localized: "To \(data.destination.city)"), data.destination.flag), radius: 88, size: 16, onTop: true)
                CircularText(text: arcText(String(localized: "From \(data.origin.city)"), data.origin.flag), radius: 100, size: 15, onTop: false)

                Circle().frame(width: 6, height: 6).offset(x: -109)
                Circle().frame(width: 6, height: 6).offset(x: 109)

                VStack(spacing: 2) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 20))
                    Text(data.arrivalDate ?? "")
                        .font(.system(size: 27, weight: .heavy))
                        .tracking(-0.5)
                    Text([data.arrivalYear, data.arrivalTime].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 14, weight: .semibold))
                    Text("twofold")
                        .font(.system(size: 13, design: .serif))
                        .opacity(0.7)
                        .padding(.top, 4)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 120)
                .offset(y: 8)
            }
            .foregroundStyle(Theme.Share.stampInk)
            .rotationEffect(.degrees(-9))
        }
        .frame(width: 280, height: 280)
        .stickerShadow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Passport stamp sticker: to \(data.destination.city), from \(data.origin.city), \(data.arrivalDate ?? "") \(data.arrivalYear ?? ""), \(data.arrivalTime ?? "")"))
    }

    /// The flag goes last so it always sits right after the city name.
    private func arcText(_ words: String, _ flag: String?) -> String {
        flag.map { "\(words) \($0)" } ?? words
    }
}

// MARK: - Previews

#Preview("All six, QF80") {
    ScrollView {
        VStack(spacing: 32) {
            ForEach(FlightStickerKind.allCases) { kind in
                FlightSticker(kind: kind, data: .sample)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
    .background(Theme.Share.checkerB)
}

//
//  FlightShareView.swift
//  Twofold
//
//  The flight's Share sheet (SHARE_REDESIGN.md §4): six transparent stickers on a checkerboard,
//  ordered by where the flight is, with chips that stay in step with swiping. Add to Instagram
//  story when Instagram and a Meta App ID are both there; otherwise the system share sheet leads.
//

import PostHog
import SwiftUI

struct FlightShareView: View {
    let flight: Flight

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selection: FlightStickerKind?
    @State private var image: UIImage?
    @State private var confirmation: String?
    @State private var instagramAvailable = false
    @State private var previewWidth: CGFloat = 361

    private var data: FlightStickerData {
        FlightStickerData(flight: flight, me: appModel.currentUser, partner: appModel.partner)
    }

    private var kinds: [FlightStickerKind] { FlightStickerKind.ordered(for: FlightMoment(flight.status)) }
    private var current: FlightStickerKind { selection ?? kinds[0] }

    var body: some View {
        VStack(spacing: 0) {
            ShareSheetHeader { dismiss() }

            ScrollView {
                VStack(spacing: 0) {
                    preview
                        .padding(.top, 24)
                        .padding(.horizontal, Theme.Spacing.md)

                    Text("\(FlightMoment(flight.status).hint) · swipe for more")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 12)

                    chips
                        .padding(.top, 14)
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            actions
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.sm)
        }
        .background(ScreenBackground())
        .overlay(alignment: .bottom) {
            if let confirmation {
                ShareConfirmation(message: confirmation)
                    .padding(.bottom, 140)
                    .transition(.opacity)
            }
        }
        .onAppear { instagramAvailable = InstagramStories.isAvailable }
        .task(id: current) {
            await AvatarView.prefetch(data.traveller)
            image = render()
        }
        .postHogScreenView("Flight Tracking: Share")
    }

    // MARK: - Preview

    /// The sticker at its real size on a checkerboard that shows where it's transparent; scaled
    /// down only when the screen is narrower than the 361pt preview.
    private var preview: some View {
        let scale = min(1, previewWidth / 361)
        return TabView(selection: Binding(get: { current }, set: { selection = $0 })) {
            ForEach(kinds) { kind in
                FlightSticker(kind: kind, data: data)
                    .scaleEffect(scale)
                    .tag(kind)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: 361)
        .frame(height: 450 * scale)
        .background(Checkerboard())
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.Share.nightLine, lineWidth: 1))
        .animation(reduceMotion ? nil : .default, value: current)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { previewWidth = $0 }
    }

    private var chips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(kinds) { kind in
                        let isSelected = kind == current
                        Button {
                            selection = kind
                        } label: {
                            Text(LocalizedStringKey(kind.rawValue))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                                .padding(.horizontal, Theme.Spacing.md)
                                .frame(minHeight: 40)
                                .background(isSelected ? Theme.segmentSelected : Theme.segmentTrack, in: Capsule())
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .id(kind)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
            .onChange(of: current) { _, kind in
                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(kind, anchor: .center) }
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if instagramAvailable {
                Button {
                    shareToInstagram()
                } label: {
                    Label("Add to Instagram story", systemImage: "plus.square")
                }
                .buttonStyle(.twofoldPrimary)
            } else if let image {
                ShareLink(item: Image(uiImage: image), preview: SharePreview("\(current.rawValue) sticker", image: Image(uiImage: image))) {
                    Label("Share image", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.twofoldPrimary)
            }

            HStack(spacing: Theme.Spacing.sm) {
                // With Instagram leading, the system sheet is still a tap away for everywhere else.
                if instagramAvailable, let image {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("\(current.rawValue) sticker", image: Image(uiImage: image))) {
                        Text("Share image")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                ShareTextButton(title: "Save to Photos") { save() }
                ShareTextButton(title: "Copy as text") { copy() }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    /// Rendered fresh for each export, so the live sticker carries the latest progress.
    @MainActor
    private func render() -> UIImage? {
        FlightSticker(kind: current, data: data).renderedImage()
    }

    private func shareToInstagram() {
        Task {
            await AvatarView.prefetch(data.traveller)
            guard let sticker = render() else { return }
            let opened = await InstagramStories.share(sticker: sticker, topColor: Theme.Share.storyBackgroundTop, bottomColor: Theme.Share.storyBackgroundBottom)
            if !opened { confirm(String(localized: "Couldn't open Instagram")) }
        }
    }

    private func save() {
        Task {
            guard let sticker = render() else { return }
            do {
                try await SharePhotoSaver.save(sticker)
                confirm(String(localized: "Saved to Photos"))
            } catch {
                confirm(String(localized: "Couldn't save — allow Twofold to add photos in Settings"))
            }
        }
    }

    private func copy() {
        let data = self.data
        var lines = ["\(data.flightNumber) · \(data.origin.city) (\(data.origin.code)) → \(data.destination.city) (\(data.destination.code))"]
        if let date = data.departureDate, let time = data.departureTime {
            lines.append(String(localized: "Departs \(date), \(time)"))
        }
        if let date = data.arrivalDate, let time = data.arrivalTime {
            lines.append(String(localized: "Arrives \(date), \(time)"))
        }
        let facts = [data.duration, data.distance].compactMap { $0 }
        if !facts.isEmpty { lines.append(facts.joined(separator: " · ")) }
        lines += ["", "via twofold"]
        UIPasteboard.general.string = lines.joined(separator: "\n")
        confirm(String(localized: "Copied"))
    }

    private func confirm(_ message: String) {
        withAnimation { confirmation = message }
        UIAccessibility.post(notification: .announcement, argument: message)
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { confirmation = nil }
        }
    }
}

#Preview {
    FlightShareView(flight: MockData.activeFlight)
        .environment(AppModel())
}

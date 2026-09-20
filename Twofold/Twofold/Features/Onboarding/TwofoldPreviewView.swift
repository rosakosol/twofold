//
//  TwofoldPreviewView.swift
//  Twofold
//
//  Reflects back exactly what's been entered so far — no fabricated countdown or flight
//  when nothing was added. Reached only after either a real flight or a real memory has been
//  added (the flight step's own skip lands on the mandatory memory step instead), so there's
//  always something real to celebrate — hence the confetti + congrats treatment, reusing the
//  same celebration pattern as PurchaseSuccessView (spring-scaled centerpiece + success haptic)
//  rather than inventing a new one.
//

import SwiftUI
import UIKit

struct TwofoldPreviewView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(AppModel.self) private var appModel
    @State private var didCelebrate = false
    @State private var heartScale: CGFloat = 0.6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var trip: Trip? { appModel.upcomingTrips.first }

    private var daysToGo: Int? {
        guard let trip else { return nil }
        let days = Calendar.current.dateComponents([.day], from: .now, to: trip.departureDate).day ?? 0
        return max(0, days)
    }

    private var daysTogether: Int? {
        guard let anniversaryDate = onboarding.anniversaryDate else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: anniversaryDate, to: .now).day ?? 0)
    }

    private var selfImage: Image? {
        onboarding.selfPhotoData.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))
    }

    private var partnerImage: Image? {
        onboarding.partnerPhotoData.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))
    }

    var body: some View {
        OnboardingScaffold(
            title: "Your Twofold is ready",
            // The mark itself, beating, instead of a heart emoji in the string — see
            // `BeatingTitleMark`. Sized against `.title`, so it stays the height of the words.
            inlineTitleAccessoryImageName: "GlobeHeart",
            subtitle: "You're all set! Here's to closing the distance.",
            content: {
                VStack(spacing: Theme.Spacing.md) {
                    Text("🎉")
                        .font(.system(size: 40))
                        .scaleEffect(heartScale)
                        .frame(maxWidth: .infinity)
                        .onAppear {
                            if reduceMotion {
                                heartScale = 1.0
                            } else {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) {
                                    heartScale = 1.0
                                }
                            }
                            didCelebrate = true
                        }

                    // Same avatar-pair design ConnectedRevealView's "You're connected" moment
                    // uses (ring'd circles either side of a "+"), reused here rather than this
                    // screen inventing its own card-wrapped, heart-divided layout — self on the
                    // left, partner on the right (this screen's own convention; unlike
                    // ConnectedRevealView's partner-then-self order). Sized to match
                    // `PartnerConnectedView`'s own post-pairing celebration (128pt), not the
                    // smaller 64pt this used before. 88 rather than that screen's 128: this one
                    // also has to fit a countdown card, the memory just saved, and a button,
                    // without scrolling.
                    HStack(spacing: Theme.Spacing.lg) {
                        VStack(spacing: Theme.Spacing.xs) {
                            avatarCircle(selfImage, size: 88)
                            Text(onboarding.firstName.isEmpty ? "You" : onboarding.firstName)
                                .font(.subheadline)
                        }
                        Image(systemName: "plus")
                            .foregroundStyle(Theme.subtleInk)
                        VStack(spacing: Theme.Spacing.xs) {
                            avatarCircle(partnerImage, size: 88)
                            Text(onboarding.partnerName.isEmpty ? "Partner" : onboarding.partnerName)
                                .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    if let trip, let daysToGo {
                        SectionCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Next reunion")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.subtleInk)
                                    Text(daysToGo == 0 ? "Today 💛" : "\(daysToGo) days to go")
                                        .font(.title2.weight(.bold))
                                    if let flight = trip.mostRelevantFlight {
                                        Text("\(flight.flightNumber) · \(trip.origin.displayCity) → \(trip.destination.displayCity)")
                                            .font(.caption)
                                            .foregroundStyle(Theme.subtleInk)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let daysTogether {
                        SectionCard {
                            StatTile(icon: "heart.fill", value: "\(daysTogether)", label: "Days together", tint: Theme.heartRed)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        SectionCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("No trips yet")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Add a flight anytime to start your countdown.")
                                        .font(.caption)
                                        .foregroundStyle(Theme.subtleInk)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // The memory just saved on the mandatory `FirstMemoryView` step right before
                    // this screen — `.last` since onboarding only ever adds that one memory, so
                    // `appModel.memories` is otherwise still empty at this point.
                    if let memory = appModel.memories.last {
                        SectionCard {
                            HStack(spacing: Theme.Spacing.md) {
                                MemoryPhotoView(memory: memory, cornerRadius: 12)
                                    .frame(width: 56, height: 56)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(memory.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                    if let place = memory.place {
                                        Text(place.city)
                                            .font(.caption)
                                            .foregroundStyle(Theme.subtleInk)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            },
            primaryTitle: "Continue",
            primaryAction: {
                guard onboarding.isResumingAuthenticatedAccount else {
                    onboarding.path.append(.saveAccount)
                    return
                }
                // Same boundary `SaveAccountView.finish` uses, minus the sign-up it exists to do:
                // everything sitting in `OnboardingModel` gets written to the profile that the
                // website already created. Doing it here rather than later keeps the rule that
                // nothing persists until this point in the flow, whichever way the account arrived.
                Task {
                    await appModel.applyOnboardingAccount(onboarding)
                    if !appModel.hasCouple { onboarding.path.append(.invitePartner) }
                }
            }
        )
        // Over the whole screen, not pinned to the emoji.
        //
        // This was `.overlay` on the 🎉, so every particle was laid out inside a 64pt glyph — a
        // burst the size of a postage stamp, which is what "a small stream from the emoji" was.
        // The stream itself was a separate bug in ConfettiBurstView's seeding; both had to go.
        .overlay {
            ConfettiBurstView(trigger: didCelebrate, style: .shower)
        }
        .sensoryFeedback(.success, trigger: didCelebrate)
    }

    private func avatarCircle(_ image: Image?, size: CGFloat = 56) -> some View {
        ZStack {
            if let image {
                image.resizable().scaledToFill()
            } else {
                Circle().fill(Theme.cardBackground)
                // Scales with the circle itself — at this screen's 88pt, a fixed body-size icon
                // looked lost in the middle.
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(Theme.subtleInk)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}

#Preview {
    NavigationStack {
        TwofoldPreviewView()
    }
    .environment(OnboardingModel())
    .environment(AppModel())
}

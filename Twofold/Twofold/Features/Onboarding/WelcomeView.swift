//
//  WelcomeView.swift
//  Twofold
//

import SwiftUI
import MapKit

struct WelcomeView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(AppModel.self) private var appModel

    @State private var showingSignIn = false
    @State private var iconPulsing = false
    @State private var accountDeletedAlert: String?

    // Centered further east/south than a plain Europe/Africa view so Australia is in frame
    // alongside Asia and Africa; distance bumped up slightly to fit that wider span.
    private static let globeCenter = CLLocationCoordinate2D(
        latitude: -20,
        longitude: 115
    )

    @State private var globeCamera: MapCameraPosition = .camera(
        MapCamera(
            centerCoordinate: globeCenter,
            distance: 30_000_000,
            heading: 0,
            pitch: 0
        )
    )

    var body: some View {
        ZStack {
            // Same real MapKit-as-3D-globe technique used throughout the app.
            // This globe is decorative rather than interactive.
            Map(
                position: $globeCamera,
                interactionModes: []
            )
            .mapStyle(
                .imagery(elevation: .realistic)
            )
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .padding(.bottom, -80)

            // Twofold brand wash
            LinearGradient(
                colors: [
                    Color(hex: "1E3A5F").opacity(0.82),
                    Color(hex: "3E7CA6").opacity(0.78),
                    Color(hex: "6FBF8B").opacity(0.82),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                // MARK: - Brand

                VStack(spacing: Theme.Spacing.md) {
                    Image("GlobeHeart")
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: 96,
                            height: 96
                        )
                        .scaleEffect(
                            iconPulsing ? 1.08 : 1.0
                        )
                        .onAppear {
                            withAnimation(
                                .easeInOut(duration: 1.1)
                                .repeatForever(
                                    autoreverses: true
                                )
                            ) {
                                iconPulsing = true
                            }
                        }

                    Text("twofold")
                        .font(
                            .system(
                                size: 56,
                                weight: .regular,
                                design: .serif
                            )
                        )
                        .foregroundStyle(.white)
                }

                Spacer()

                // MARK: - Actions

                VStack(spacing: Theme.Spacing.md) {
                    Button {
                        onboarding.role = .inviter
                        onboarding.path.append(.situation)
                    } label: {
                        Text("Get started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.white, in: Capsule())
                            .foregroundStyle(Theme.ink)
                    }

                    Button {
                        showingSignIn = true
                    } label: {
                        Text("I have an account or invite")
                            .font(
                                .subheadline.weight(.medium)
                            )
                            .foregroundStyle(.white)
                    }
                }
                .padding(
                    .horizontal,
                    Theme.Spacing.lg
                )
                .padding(
                    .bottom,
                    Theme.Spacing.xl
                )
            }
        }
        .sheet(
            isPresented: $showingSignIn
        ) {
            SignInView(
                onUseInvite: {
                    showingSignIn = false
                    onboarding.role = .invitee
                    onboarding.hasAccount = false
                    onboarding.path.append(
                        .enterPartnerCode
                    )
                }
            )
        }
        .onAppear {
            // Covers the cold-launch path: a stale local session from before this account was
            // deleted just got silently signed back out by `loadSignedInState()`, landing here
            // rather than resuming straight into the app. Read once and clear, same as
            // `SignInView`'s explicit sign-in path.
            if let message = appModel.accountDeletedMessage {
                accountDeletedAlert = message
                appModel.accountDeletedMessage = nil
            }
        }
        .alert("Account deleted", isPresented: Binding(
            get: { accountDeletedAlert != nil },
            set: { if !$0 { accountDeletedAlert = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(accountDeletedAlert ?? "")
        }
    }
}

#Preview {
    WelcomeView()
        .environment(OnboardingModel())
        .environment(AppModel())
}

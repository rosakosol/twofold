//
//  WelcomeView.swift
//  Twofold
//

import SwiftUI
import MapKit

struct WelcomeView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var showingSignIn = false
    private static let globeCenter = CLLocationCoordinate2D(latitude: 15, longitude: 20)
    @State private var globeCamera: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: globeCenter, distance: 24_000_000, heading: 0, pitch: 0)
    )

    var body: some View {
        ZStack {
            // Same real MapKit-as-3D-globe technique used throughout the app (see
            // RelationshipGlobeView) — not an SF Symbol watermark — with a slow continuous
            // rotation, faded under the gradient so the welcome copy stays readable. Spins via
            // `heading` (not `centerCoordinate`) — MapKit throws if longitude ever leaves
            // -180...180, so animating heading 0→360 is what actually keeps this valid; 360
            // renders identically to 0, so the reset at each loop is seamless.
            Map(position: $globeCamera, interactionModes: [])
                .mapStyle(.hybrid(elevation: .realistic))
                .allowsHitTesting(false)
                .ignoresSafeArea()
                .onAppear {
                    withAnimation(.linear(duration: 90).repeatForever(autoreverses: false)) {
                        globeCamera = .camera(
                            MapCamera(centerCoordinate: Self.globeCenter, distance: 24_000_000, heading: 360, pitch: 0)
                        )
                    }
                }

            LinearGradient(
                colors: [Color(hex: "1E3A5F").opacity(0.82), Color(hex: "3E7CA6").opacity(0.78), Color(hex: "6FBF8B").opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 40))
                        .foregroundStyle(.white)
                    Text("twofold")
                        .font(.system(.title, design: .serif))
                        .foregroundStyle(.white)
                }

                Text("Feel closer, even when\nyou're far apart.")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                Spacer()

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
                        onboarding.role = .invitee
                        onboarding.hasAccount = false
                        onboarding.path.append(.enterPartnerCode)
                    } label: {
                        Text("I have an invite")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }

                    Button {
                        showingSignIn = true
                    } label: {
                        Text("Already have an account? Sign in")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .sheet(isPresented: $showingSignIn) { SignInView() }
    }
}

#Preview {
    WelcomeView()
        .environment(OnboardingModel())
}

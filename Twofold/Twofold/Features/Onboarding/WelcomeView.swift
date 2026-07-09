//
//  WelcomeView.swift
//  Twofold
//

import SwiftUI
import MapKit

struct WelcomeView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var showingSignIn = false
    // Centered further east/south than a plain Europe/Africa view so Australia is in frame
    // alongside Asia and Africa; distance bumped up slightly to fit that wider span.
    private static let globeCenter = CLLocationCoordinate2D(latitude: -20, longitude: 115)
    @State private var globeCamera: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: globeCenter, distance: 30_000_000, heading: 0, pitch: 0)
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
                .mapStyle(.imagery(elevation: .realistic))
                .allowsHitTesting(false)
                .ignoresSafeArea()
                .onAppear {
                    withAnimation(.linear(duration: 90).repeatForever(autoreverses: false)) {
                        globeCamera = .camera(
                            MapCamera(centerCoordinate: Self.globeCenter, distance: 30_000_000, heading: 360, pitch: 0)
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

                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 72))
                        .foregroundStyle(.white)
                    Text("twofold")
                        .font(.system(size: 56, weight: .regular, design: .serif))
                        .foregroundStyle(.white)
                }

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
                        showingSignIn = true
                    } label: {
                        Text("I have an account or invite")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .sheet(isPresented: $showingSignIn) {
            SignInView(onUseInvite: {
                showingSignIn = false
                onboarding.role = .invitee
                onboarding.hasAccount = false
                onboarding.path.append(.enterPartnerCode)
            })
        }
    }
}

#Preview {
    WelcomeView()
        .environment(OnboardingModel())
}

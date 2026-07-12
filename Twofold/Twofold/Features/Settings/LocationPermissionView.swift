//
//  LocationPermissionView.swift
//  Twofold
//
//  Read-only status + a link to the system Settings page for this app's location permission —
//  the actual request flow (HomeLocationService, "use my current location") lives on
//  AboutYouView where it's actually used; this screen just explains what it's for and lets you
//  change your mind after the fact.
//

import CoreLocation
import SwiftUI

struct LocationPermissionView: View {
    @State private var status: CLAuthorizationStatus = CLLocationManager().authorizationStatus

    private var statusLabel: String {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not requested yet"
        @unknown default: "Unknown"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                SectionCard {
                    HStack {
                        Text("Status").foregroundStyle(Theme.subtleInk)
                        Spacer()
                        Text(statusLabel).foregroundStyle(Theme.ink)
                    }
                }

                SectionCard {
                    Text("Twofold can use your location to suggest your home city and timezone automatically, instead of searching for it by hand — see “About you”.")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        SettingsRow(title: "Open iOS Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Location Permission")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            status = CLLocationManager().authorizationStatus
        }
    }
}

#Preview {
    NavigationStack {
        LocationPermissionView()
    }
}

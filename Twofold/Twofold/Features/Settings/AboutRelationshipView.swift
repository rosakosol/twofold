//
//  AboutRelationshipView.swift
//  Twofold
//
//  Couple-level settings — currently just the anniversary date. Split out of SettingsView as
//  part of the Settings/Profile IA restructure. This is the sole place anniversary editing
//  lives once a couple is connected — PartnerSetupView keeps its own copy only for the
//  pre-connection first-time-setup flow, so getting a partner set up doesn't require bouncing
//  between two screens.
//

import SwiftUI

struct AboutRelationshipView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var anniversaryDate: Date = .now
    @State private var isSaving = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                SectionCard {
                    Text("Anniversary").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.subtleInk)
                    DatePicker("Together since", selection: $anniversaryDate, in: ...Date.now, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("About Your Relationship")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: save) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save").fontWeight(.semibold)
                    }
                }
                .disabled(isSaving)
            }
        }
        .onAppear {
            anniversaryDate = appModel.couple.startedDatingOn
        }
    }

    private func save() {
        isSaving = true
        Task {
            await appModel.updateAnniversaryDate(anniversaryDate)
            isSaving = false
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        AboutRelationshipView()
    }
    .environment(AppModel())
}

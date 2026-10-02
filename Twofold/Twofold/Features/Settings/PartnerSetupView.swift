//
//  PartnerSetupView.swift
//  Twofold
//
//  Every partner-relationship-scoped screen in one place — reachable both pre-connection
//  (Home's "Set up your partner" card, and Settings' "Connect with your partner" row) and
//  post-connection (Settings' "About your partner" row, same destination, different label).
//  Pre-connection it's name/photo/city/anniversary plus the connect step, so first-time setup
//  doesn't require bouncing between screens. Once connected it keeps the anniversary and adds
//  Archived Data and Remove Partner.
//
//  The anniversary used to live on a second screen once a couple was connected, behind its own
//  "About your relationship" row in Settings. Two rows, and no way to predict which of them held
//  the date you wanted — "your relationship" and "your partner" describe the same two people. So
//  there is one row now, and this is it. That screen's date-picker bound and its
//  happy-anniversary moment both came across rather than being dropped on the way.
//

import PostHog
import SwiftUI

struct PartnerSetupView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var partnerName: String = ""
    @State private var partnerCity: Place?
    @State private var anniversaryDate: Date = .now
    @State private var partnerAvatarError: String?
    @State private var isSaving = false
    @State private var showingHappyAnniversary = false

    /// End of today rather than the live `Date.now` instant.
    ///
    /// Inherited from the screen this absorbed, along with the reason: bounding at the exact
    /// current instant silently puts "today" out of reach whenever the picker's held time-of-day
    /// — here whatever `couple.startedDatingOn` carries — falls later in the day than the clock.
    /// This screen previously used `...Date.now` and had that bug; the merge is a good moment to
    /// stop having it.
    private var latestSelectableDate: Date {
        let startOfToday = Calendar.current.startOfDay(for: .now)
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: startOfToday) ?? .now
    }

    /// Month and day against today, deliberately not `Calendar.isDateInToday`, which also wants
    /// the year to match and so is essentially never true of a real anniversary.
    private var isAnniversaryToday: Bool {
        let calendar = Calendar.current
        let picked = calendar.dateComponents([.month, .day], from: anniversaryDate)
        let today = calendar.dateComponents([.month, .day], from: .now)
        return picked.month == today.month && picked.day == today.day
    }

    var body: some View {
        @Bindable var appModel = appModel

        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    RoundPhotoPicker(placeholderSystemImage: "person.fill", initialImageURL: appModel.partner.avatarURL, size: 96) { data in
                        Task {
                            do {
                                try await appModel.updatePartnerAvatar(imageData: data)
                                partnerAvatarError = nil
                            } catch {
                                partnerAvatarError = error.localizedDescription
                            }
                        }
                    }
                    .padding(.top, Theme.Spacing.md)

                    if let partnerAvatarError {
                        Text(partnerAvatarError)
                            .font(.caption)
                            .foregroundStyle(Theme.error)
                    }

                    SectionCard {
                        Text("Partner's name").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        TextField("Partner's name", text: $partnerName)
                            .textContentType(.givenName)
                            .textInputAutocapitalization(.words)
                            .padding()
                            .background(Theme.backgroundGradient.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        // A nickname is always personal — your partner has their own
                        // independent name for you, and neither side ever overwrites the
                        // other's.
                        Text("Just for you - they won't see this name or photo.")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if appModel.partnerConnected {
                        SectionCard {
                            HStack {
                                Text("City").foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Text(appModel.partner.homeCity?.displayCity ?? "—").foregroundStyle(Theme.textPrimary)
                            }
                        }
                    } else {
                        SectionCard {
                            Text("Partner's city").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                            CityMenuPicker(label: "Partner's city", selection: $partnerCity)
                        }
                    }

                    // Read-only, and only once connected: it comes from their profile row, not
                    // from a field here. There is deliberately no way to type a birthday on
                    // somebody else's behalf — one date, authored by whoever it belongs to, so the
                    // reminder cannot end up with two answers. Until they add one there is nothing
                    // to show and nothing this person can do about it except ask.
                    if appModel.partnerConnected {
                        SectionCard {
                            HStack {
                                Text("Birthday").foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Text(appModel.partner.birthday?.displayText ?? "Not set")
                                    .foregroundStyle(appModel.partner.birthday == nil ? Theme.textSecondary : Theme.textPrimary)
                            }
                            if appModel.partner.birthday == nil {
                                Text("Only \(appModel.partner.name) can add this, from their own Account screen.")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }

                    // Shown whether or not a partner is connected. It is the one field here that
                    // belongs to the couple rather than to this person's private notes about them,
                    // and it used to disappear from this screen the moment they paired.
                    SectionCard {
                        Text("Anniversary").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        DatePicker("Together since", selection: $anniversaryDate, in: ...latestSelectableDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }

                    if !appModel.partnerConnected {
                        PendingConnectionRequestsCard()
                        PartnerConnectCard(inviteCode: $appModel.inviteCode)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(ScreenBackground())
            .navigationTitle("Your Partner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
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
                // "Partner" is the unpaired placeholder name — an empty field reads better
                // than prefilling that literal word as if it were a saved nickname.
                partnerName = appModel.partner.name == "Partner" ? "" : appModel.partner.name
                partnerCity = appModel.partner.homeCity
                anniversaryDate = appModel.couple.startedDatingOn
            }
            .task {
                await appModel.refreshPendingConnectionRequests()
            }
        }
        .postHogScreenView("Settings: Partner Setup")
        .fullScreenCover(isPresented: $showingHappyAnniversary, onDismiss: dismiss.callAsFunction) {
            HappyAnniversaryView(
                years: max(0, Calendar.current.dateComponents([.year], from: anniversaryDate, to: .now).year ?? 0),
                onContinue: { showingHappyAnniversary = false }
            )
        }
    }

    private func save() {
        isSaving = true
        Task {
            await appModel.updatePartnerName(partnerName)
            // City stays pre-connection only: once paired it is real shared data rather than a
            // guess, and the field above is read-only, so writing it back would just re-save an
            // unchanged value. The anniversary is different — it is editable in both states now,
            // so it saves in both.
            if !appModel.partnerConnected, let partnerCity {
                await appModel.updatePartnerHomeCity(partnerCity)
            }
            await appModel.updateAnniversaryDate(anniversaryDate)
            isSaving = false
            // Setting the date to today is worth marking rather than silently closing. Carried
            // over from the screen this absorbed; without it the merge would have quietly deleted
            // the one moment of delight in Settings.
            if isAnniversaryToday {
                showingHappyAnniversary = true
            } else {
                dismiss()
            }
        }
    }
}

#Preview {
    PartnerSetupView()
        .environment(AppModel())
}

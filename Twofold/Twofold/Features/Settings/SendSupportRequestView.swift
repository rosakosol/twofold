//
//  SendSupportRequestView.swift
//  Twofold
//
//  The app's single "Contact Support" form — reached from SupportView's "Still need help?"
//  section, and from every game screen's "Report a Problem" (which opens it preset to
//  .gameIssue with the deck/card attached). Sends the email server-side via
//  HelpService/submit-help-message, with a category so support can triage without reading the
//  message first. Feedback is just a category here now; there's no separate feedback screen.
//

import PostHog
import SwiftUI

struct SendSupportRequestView: View {
    /// Preset by the caller (e.g. .gameIssue from a game screen) but still user-changeable —
    /// someone who opened it mid-game may well want to file something else.
    private let gameContext: GameIssueContext?

    @Environment(\.dismiss) private var dismiss
    /// Optional so the field can start on a "Select a category" placeholder. It used to default
    /// to `.other`, which quietly sent the least useful value for triage whenever someone didn't
    /// notice the control — an unset category that blocks sending is better than a wrong one.
    /// Game screens still preset `.gameIssue`.
    @State private var category: SupportRequestCategory?
    @State private var message = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didSend = false

    init(initialCategory: SupportRequestCategory? = nil, gameContext: GameIssueContext? = nil) {
        self.gameContext = gameContext
        _category = State(initialValue: initialCategory)
    }

    private var canSend: Bool {
        category != nil
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Category").font(.caption).foregroundStyle(Theme.subtleInk)
                        // A Menu wrapping the Picker, rather than `.pickerStyle(.menu)` directly:
                        // that style sizes its button to its own content, so the card stretched
                        // full width but only the words inside it were tappable. Driving the menu
                        // from a custom label makes the whole row the control, and the inline
                        // Picker still checkmarks the current selection.
                        Menu {
                            Picker("Category", selection: $category) {
                                ForEach(SupportRequestCategory.allCases) { option in
                                    Text(option.rawValue).tag(Optional(option))
                                }
                            }
                            .pickerStyle(.inline)
                        } label: {
                            HStack {
                                Text(category?.rawValue ?? "Select a category")
                                    .foregroundStyle(category == nil ? Theme.subtleInk : Theme.ink)
                                Spacer(minLength: Theme.Spacing.sm)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(Theme.subtleInk)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    // Shown rather than attached silently — the reporter can see exactly which
                    // deck/card is going along with their message.
                    if let gameContext {
                        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                            Image(systemName: "paperclip")
                            Text(gameContext.summary)
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                        .padding(Theme.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("What's going on?").font(.caption).foregroundStyle(Theme.subtleInk)
                        TextField("Describe the issue", text: $message, axis: .vertical)
                            .lineLimit(8...16)
                            // Horizontal inset matches the category control above (and the fields
                            // in ForgotPasswordView) so the text in both lines up; vertical stays
                            // at `sm` to keep an 8–16 line box from growing unnecessarily tall.
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }

                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(Theme.heartRed)
                    }

                    Button(action: send) {
                        HStack {
                            if isSaving { ProgressView().tint(.white) }
                            Text(isSaving ? "Sending…" : "Send to Support")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundStyle(.white)
                        .background(
                            canSend ? AnyShapeStyle(Theme.primaryButtonGradient) : AnyShapeStyle(Theme.subtleInk.opacity(0.3)),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        )
                    }
                    .disabled(!canSend)
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Contact Support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Message sent", isPresented: $didSend) {
                Button("Done") { dismiss() }
            } message: {
                Text("Our support team will get back to you by email.")
            }
        }
        .postHogScreenView("Settings: Contact Support")
    }

    private func send() {
        // `canSend` already gates the button on this; the guard is what lets the call below take
        // a non-optional category without a force-unwrap.
        guard let category else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await HelpService.submitSupportRequest(category: category, message: message, game: gameContext)
                isSaving = false
                didSend = true
            } catch {
                errorMessage = (error as? HelpServiceError)?.errorDescription ?? "Couldn't send your message. Try again."
                isSaving = false
            }
        }
    }
}

#Preview {
    SendSupportRequestView()
}

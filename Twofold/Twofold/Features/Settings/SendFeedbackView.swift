//
//  SendFeedbackView.swift
//  Twofold
//
//  Inline "Send Feedback" form — actually sends the email server-side (via
//  HelpService/submit-help-message), rather than handing off to the device's Mail app.
//

import PostHog
import SwiftUI

struct SendFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didSend = false

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    // Pushed (NavigationLink from HelpView), not sheeted — no own NavigationStack/Cancel button,
    // same convention as this list's other destination, DisconnectPartnerView: the containing
    // stack already supplies the back button.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Tell us what's on your mind — a bug, an idea, or just how it's going. We read every message.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)

                TextField("What would you like to tell us?", text: $message, axis: .vertical)
                    .lineLimit(8...16)
                    .padding(Theme.Spacing.sm)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(Theme.heartRed)
                }

                Button(action: send) {
                    HStack {
                        if isSaving { ProgressView().tint(.white) }
                        Text(isSaving ? "Sending…" : "Send Feedback")
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
        .navigationTitle("Send Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Thanks for the feedback!", isPresented: $didSend) {
            Button("Done") { dismiss() }
        } message: {
            Text("We've received your message.")
        }
        .postHogScreenView("Settings: Send Feedback")
    }

    private func send() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await HelpService.submitFeedback(message: message)
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
    NavigationStack {
        SendFeedbackView()
    }
}

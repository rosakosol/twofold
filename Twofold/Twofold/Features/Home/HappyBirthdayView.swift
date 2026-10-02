//
//  HappyBirthdayView.swift
//  Twofold
//
//  The birthday itself, marked. Shown once on the day, for either person's.
//
//  Two variants, because the two occasions are not the same occasion. Your own is a greeting and
//  nothing more — there is nobody to act towards, and a button would only ask you to do something
//  about yourself. Your partner's is the one with something to do, so it carries the message, and
//  the message is the point: a screen that says "it's Max's birthday" and then offers no way to
//  say anything is a reminder that arrives too late to be useful.
//
//  Same shape as `HappyAnniversaryView`, deliberately — the one full-screen celebratory moment
//  this app already had, and the pattern people will have seen once before by the time they meet
//  this one. It takes its `onContinue` from the caller for the same reason that one does.
//

import SwiftUI

struct HappyBirthdayView: View {
    /// Whose birthday. `nil` means it is yours — there is no name to show, and the copy changes.
    var partnerName: String?
    var onContinue: () -> Void
    /// Sends the typed message. Nil for your own birthday, where there is nobody to send to.
    var onSendMessage: ((String) async -> Bool)?

    @State private var contentVisible = false
    @State private var message = ""
    @State private var isSending = false
    @State private var didSend = false
    @State private var sendFailed = false
    @FocusState private var messageFocused: Bool

    private var isOwnBirthday: Bool { partnerName == nil }

    private var title: String {
        isOwnBirthday ? "Happy birthday!" : "It's \(partnerName ?? "their")'s birthday!"
    }

    private var subtitle: String {
        isOwnBirthday
            ? "Hope today is a good one."
            : "Today's the day. Say something — they'll get it straight away."
    }

    var body: some View {
        ZStack {
            Theme.coralGradient
            .ignoresSafeArea()

            AnimatedBalloonsView()

            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    Spacer(minLength: Theme.Spacing.xl)

                    Text("🎂")
                        .font(.system(size: 64))
                        .scaleEffect(contentVisible ? 1 : 0.6)
                        .opacity(contentVisible ? 1 : 0)

                    VStack(spacing: Theme.Spacing.sm) {
                        Text(title)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .multilineTextAlignment(.center)
                        Text(subtitle)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .opacity(0.9)
                    }
                    .foregroundStyle(.white)
                    .opacity(contentVisible ? 1 : 0)

                    if let onSendMessage {
                        messageComposer(send: onSendMessage)
                    }

                    Spacer(minLength: Theme.Spacing.lg)

                    Button(action: onContinue) {
                        Text(didSend || isOwnBirthday ? "Done" : "Not now")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.sm)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .opacity(0.9)
                }
                .padding(Theme.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { contentVisible = true }
        }
    }

    @ViewBuilder
    private func messageComposer(send: @escaping (String) async -> Bool) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            if didSend {
                // Replaces the field rather than sitting under it. Leaving a filled-in box on
                // screen after sending invites a second send of the same words.
                Label("Sent", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
            } else {
                TextField("Happy birthday!", text: $message, axis: .vertical)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.sentences)
                    .focused($messageFocused)
                    .padding()
                    .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .foregroundStyle(Theme.inkOnFixedLight)

                if sendFailed {
                    Text("That didn't send. Try again in a moment.")
                        .font(.caption)
                        .foregroundStyle(.white)
                }

                Button {
                    messageFocused = false
                    isSending = true
                    sendFailed = false
                    Task {
                        // Empty is allowed: the notification has its own wording for a wish with
                        // no words in it, and making somebody type to press the button would be a
                        // strange gate on saying happy birthday.
                        didSend = await send(message.trimmingCharacters(in: .whitespacesAndNewlines))
                        sendFailed = !didSend
                        isSending = false
                    }
                } label: {
                    if isSending {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Send").fontWeight(.semibold).frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Theme.inkOnFixedLight)
                .disabled(isSending)
            }
        }
        .opacity(contentVisible ? 1 : 0)
    }
}

#Preview("Partner's birthday") {
    HappyBirthdayView(partnerName: "Max", onContinue: {}, onSendMessage: { _ in true })
}

#Preview("Your own") {
    HappyBirthdayView(partnerName: nil, onContinue: {})
}

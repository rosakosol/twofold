//
//  AuthField.swift
//  Twofold
//
//  The text inputs on the four screens where somebody types credentials — sign in, create
//  account, save account, reset password.
//
//  Two problems, one component.
//
//  The first was the tap target. Every one of these fields was written as `TextField(...)
//  .padding().onboardingFieldBackground()`, which paints a comfortable 50-odd point box and leaves
//  the field's *hit region* at the size of the text inside it. `.padding()` wraps a view in a
//  larger container; it does not enlarge the child's frame, and hit testing follows the child. So
//  the box you can see is roughly twice the box you can tap, the miss lands on the VStack behind,
//  and nothing happens — which is why it took several attempts to get a keyboard up. The fix needs
//  a real focus target, so it has to live inside the field rather than in the background modifier:
//  `contentShape` makes the whole box hittable and the tap hands focus to the field it wraps.
//
//  The second was that there was no way to see what you had typed. A password you cannot read is a
//  password you retype from the start on every mistake, and these screens ask for it twice.
//
//  Kept apart from `onboardingFieldBackground()`, which the other five onboarding screens still
//  use for single, non-credential fields (name, city, invite code) — this adds a focus target and
//  a reveal button, neither of which those need.
//

import SwiftUI

struct AuthField: View {
    let title: String
    @Binding var text: String
    /// Renders as a `SecureField` and gains the reveal button.
    var isSecure: Bool = false
    var textContentType: UITextContentType?
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .never

    @FocusState private var isFocused: Bool
    @State private var isRevealed = false
    /// Scales with Dynamic Type, so the box stays at least as tall as the text it holds. 52 rather
    /// than the HIG's 44 minimum because the visible box was already about this tall — the bug was
    /// never that it looked small, only that the tappable part was.
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 52

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Group {
                if isSecure && !isRevealed {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                }
            }
            .textContentType(textContentType)
            .keyboardType(keyboardType)
            .textInputAutocapitalization(autocapitalization)
            .focused($isFocused)

            if isSecure {
                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.subtleInk)
                        // 44×44 in its own right — the icon is 16pt, and an icon-sized button in
                        // the corner of a password field is the exact thing people miss.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
            }
        }
        .padding(.horizontal)
        .frame(minHeight: minHeight)
        .onboardingFieldBackground()
        // Order matters: `contentShape` has to come after the frame that gives the box its real
        // size, or it describes the text's bounds all over again.
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        // Swapping SecureField for TextField replaces the view, and the replacement is not
        // focused — so revealing a password mid-typing dismissed the keyboard and dropped the
        // caret. Handing focus back keeps typing where it was.
        .onChange(of: isRevealed) { _, _ in isFocused = true }
    }
}

#Preview {
    @Previewable @State var email = ""
    @Previewable @State var password = "hunter2"
    VStack(spacing: Theme.Spacing.md) {
        AuthField(title: "Email", text: $email, textContentType: .emailAddress, keyboardType: .emailAddress)
        AuthField(title: "Password", text: $password, isSecure: true, textContentType: .password)
    }
    .padding()
}

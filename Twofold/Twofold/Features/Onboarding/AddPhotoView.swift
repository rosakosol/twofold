//
//  AddPhotoView.swift
//  Twofold
//
//  Shown to both roles right after their account/home city (and, for an invitee, right
//  after they've actually redeemed the invite) — skippable, since a photo shouldn't block
//  getting into the app. Also lets an invitee set their own custom photo for how *they*
//  picture the inviter — independent of whatever photo the inviter picked for themself.
//

import SwiftUI
import PhotosUI
import UIKit

struct AddPhotoView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(AppModel.self) private var appModel
    @State private var isUploadingSelf = false
    @State private var isUploadingPartnerView = false
    @State private var errorMessage: String?

    private var subtitle: String {
        let partnerName = onboarding.role == .invitee ? (onboarding.inviterName ?? "your partner") : "your partner"
        return "You and \(partnerName) will have separate photos in Twofold. You can change them later in Settings."
    }

    var body: some View {
        OnboardingScaffold(
            title: "Customise your photo",
            subtitle: subtitle,
            content: {
                VStack(spacing: Theme.Spacing.xl) {
                    VStack(spacing: Theme.Spacing.sm) {
                        ZStack {
                            RoundPhotoPicker(initialImageData: nil) { data in
                                Task { await uploadSelf(data) }
                            }
                            if isUploadingSelf {
                                Circle().fill(.black.opacity(0.3)).frame(width: 100, height: 100)
                                ProgressView().tint(.white)
                            }
                        }
                        Text("Your photo").font(.caption).foregroundStyle(Theme.subtleInk)
                    }
                    .frame(maxWidth: .infinity)

                    if let inviterName = onboarding.inviterName {
                        VStack(spacing: Theme.Spacing.sm) {
                            ZStack {
                                RoundPhotoPicker(placeholderSystemImage: "person.fill", initialImageData: nil) { data in
                                    Task { await uploadPartnerView(data) }
                                }
                                if isUploadingPartnerView {
                                    Circle().fill(.black.opacity(0.3)).frame(width: 100, height: 100)
                                    ProgressView().tint(.white)
                                }
                            }
                            Text("Your photo of \(inviterName)")
                                .font(.caption)
                                .foregroundStyle(Theme.subtleInk)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.heartRed)
                            .multilineTextAlignment(.center)
                    }
                }
            },
            primaryTitle: "Continue",
            primaryAction: advance,
            primaryDisabled: isUploadingSelf || isUploadingPartnerView,
            secondaryTitle: "Skip for now",
            secondaryAction: advance
        )
    }

    private func uploadSelf(_ data: Data) async {
        isUploadingSelf = true
        errorMessage = nil
        do {
            let url = try await BackendService.uploadAvatar(imageData: data)
            appModel.couple.partnerA.avatarURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
        isUploadingSelf = false
    }

    private func uploadPartnerView(_ data: Data) async {
        isUploadingPartnerView = true
        errorMessage = nil
        do {
            let url = try await BackendService.uploadPartnerAvatar(imageData: data)
            appModel.couple.partnerB.avatarURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
        isUploadingPartnerView = false
    }

    private func advance() {
        // This screen only lives on the preserved deep-link/manual-invite path now (the
        // default "Get started" flow has its own photo-free path), which is always invitee.
        onboarding.path.append(.connectionRequestSent)
    }
}

extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension else { return self }
        let scale = maxDimension / largestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

#Preview {
    NavigationStack {
        AddPhotoView()
    }
    .environment(OnboardingModel())
    .environment(AppModel())
}

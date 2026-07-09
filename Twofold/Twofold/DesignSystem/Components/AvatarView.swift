//
//  AvatarView.swift
//  Twofold
//

import SwiftUI

/// Shows the person's uploaded photo when they have one, falling back to an
/// initials-on-gradient placeholder otherwise.
struct AvatarView: View {
    let person: Person
    var size: CGFloat = 44
    var showsRing: Bool = false

    var body: some View {
        Group {
            if let avatarURL = person.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if showsRing {
                Circle().strokeBorder(.white, lineWidth: 2)
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }

    private var placeholder: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [person.accentColor, person.accentColor.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(person.initials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    AvatarView(person: MockData.dara, size: 64, showsRing: true)
}

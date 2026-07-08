//
//  AvatarView.swift
//  Twofold
//

import SwiftUI

/// Initials-on-gradient placeholder avatar. Swap for a real photo (AsyncImage/PhotosUI) once accounts have profile pictures.
struct AvatarView: View {
    let person: Person
    var size: CGFloat = 44
    var showsRing: Bool = false

    var body: some View {
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
        .frame(width: size, height: size)
        .overlay {
            if showsRing {
                Circle().strokeBorder(.white, lineWidth: 2)
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}

#Preview {
    AvatarView(person: MockData.dara, size: 64, showsRing: true)
}

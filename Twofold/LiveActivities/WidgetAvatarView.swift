//
//  WidgetAvatarView.swift
//  LiveActivities
//
//  Local port of DesignSystem/Components/AvatarView.swift — deliberately not shared cross-target
//  (same reasoning as LiveActivityPalette.swift). Reads whichever cached photo the main app last
//  downloaded (WidgetImageCache — see WidgetSnapshotWriter's avatar fetch), never fetches its
//  own; falls back to an initials-on-gradient circle exactly like the main app's version.
//

import SwiftUI

enum WidgetPerson {
    case me, partner
}

struct WidgetAvatarView: View {
    var person: WidgetPerson
    var name: String
    var size: CGFloat = 32
    var showsRing: Bool = true

    private var imageData: Data? {
        switch person {
        case .me: WidgetImageCache.readMyAvatarImage()
        case .partner: WidgetImageCache.readPartnerAvatarImage()
        }
    }

    private var accentColor: Color {
        person == .me ? LiveActivityPalette.skyBlue : LiveActivityPalette.heartRed
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.compactMap { $0.first }.prefix(2)
        return String(letters).uppercased()
    }

    var body: some View {
        Group {
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage).resizable().scaledToFill()
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
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [accentColor, accentColor.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(initials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

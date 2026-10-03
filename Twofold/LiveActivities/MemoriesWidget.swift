//
//  MemoriesWidget.swift
//  LiveActivities
//
//  The latest memory (docs/TWOFOLD_DESIGN.md, section 7): its photo filling the widget, with the
//  title, place and date in white on a scrim along the bottom. Small, medium and large.
//
//  The photo is the one the app caches for widgets (`WidgetImageCache.readLatestMemoryImage`),
//  so the widget makes no network call of its own.
//

import SwiftUI
import WidgetKit

struct MemoriesEntry: TimelineEntry {
    let date: Date
    let memory: WidgetSnapshot.MemoryInfo?
}

struct MemoriesProvider: TimelineProvider {
    func placeholder(in context: Context) -> MemoriesEntry {
        MemoriesEntry(date: .now, memory: WidgetSnapshot.MemoryInfo(id: UUID(), title: "Our first dinner", date: .now, city: "Rome"))
    }

    func getSnapshot(in context: Context, completion: @escaping (MemoriesEntry) -> Void) {
        completion(MemoriesEntry(date: .now, memory: WidgetSnapshot.read()?.latestMemory))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MemoriesEntry>) -> Void) {
        let entry = MemoriesEntry(date: .now, memory: WidgetSnapshot.read()?.latestMemory)
        // The app reloads timelines whenever a memory is added, so this only has to catch the
        // odd case where that did not happen.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(6 * 3600))))
    }
}

/// A memory's photo as a widget background, filled and cropped, with the bottom scrim the white
/// caption sits on. Falls back to the indigo gradient when there is no photo.
struct MemoryPhotoBackground: View {
    let imageData: Data?

    var body: some View {
        ZStack {
            if let uiImage = WidgetImageDecoding.downsampled(imageData, pointSize: 400) {
                Image(uiImage: uiImage)
                    .resizable()
                    .widgetAccentedRenderingMode(.fullColor)
                    .scaledToFill()
            } else {
                Brand.indigoGradient
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            LinearGradient(colors: [.clear, .clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        }
    }
}

struct MemoriesWidgetView: View {
    let entry: MemoriesEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let memory = entry.memory {
                VStack(alignment: .leading, spacing: 2) {
                    Spacer(minLength: 0)
                    Text(memory.title.isEmpty ? "A moment" : memory.title)
                        .font(.system(size: family == .systemSmall ? 15 : 18, weight: .bold))
                        .lineLimit(2)
                        .widgetAccentable()
                    Text([memory.city, memory.date.formatted(date: .abbreviated, time: .omitted)].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12, weight: .semibold))
                        .opacity(0.92)
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .widgetSurface { MemoryPhotoBackground(imageData: WidgetImageCache.readLatestMemoryImage()) }
                .widgetURL(URL(string: "twofold://memory/\(memory.id.uuidString)"))
            } else {
                WidgetEmptyState(systemImage: "photo.on.rectangle.angled", message: "Save your first memory", gradient: Brand.indigoGradient)
                    .widgetURL(URL(string: "twofold://memories"))
            }
        }
    }
}

struct MemoriesWidget: Widget {
    let kind = "MemoriesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MemoriesProvider()) { entry in
            MemoriesWidgetView(entry: entry)
        }
        .configurationDisplayName("Memories")
        .description("Your latest memory, where and when it happened.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemMedium) {
    MemoriesWidget()
} timeline: {
    MemoriesEntry(date: .now, memory: WidgetSnapshot.MemoryInfo(id: UUID(), title: "Our first dinner", date: .now, city: "Rome"))
}

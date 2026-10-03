//
//  DailyQuestionWidget.swift
//  LiveActivities
//
//  Today's deep question (docs/TWOFOLD_DESIGN.md, section 7), on its own gradient. Your partner's
//  answer stays blurred, with "Answer to see", until you have answered yourself; until you have
//  both answered the database will not hand it over at all, so the blur is over a placeholder, not
//  over their words.
//

import SwiftUI
import WidgetKit

struct DailyQuestionEntry: TimelineEntry {
    let date: Date
    let question: WidgetSnapshot.DailyQuestionInfo?
    let partnerName: String
}

struct DailyQuestionProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyQuestionEntry {
        DailyQuestionEntry(
            date: .now,
            question: WidgetSnapshot.DailyQuestionInfo(question: "What's a small thing I do that you love?", myAnswered: false, partnerAnswered: true, partnerAnswer: nil),
            partnerName: "Partner"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyQuestionEntry) -> Void) {
        completion(entry(from: WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyQuestionEntry>) -> Void) {
        // A new question each day; answers arrive through the app reloading timelines.
        let midnight = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime) ?? .now.addingTimeInterval(86_400)
        completion(Timeline(entries: [entry(from: WidgetSnapshot.read())], policy: .after(midnight)))
    }

    private func entry(from snapshot: WidgetSnapshot?) -> DailyQuestionEntry {
        DailyQuestionEntry(date: .now, question: snapshot?.dailyQuestion, partnerName: snapshot?.partnerName ?? "Partner")
    }
}

struct DailyQuestionWidgetView: View {
    let entry: DailyQuestionEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let question = entry.question {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today's question")
                        .font(.system(size: 12, weight: .semibold))
                        .opacity(0.92)
                    Text(question.question)
                        .font(.system(size: family == .systemSmall ? 15 : 17, weight: .bold))
                        .lineLimit(family == .systemSmall ? 4 : 3)
                        .minimumScaleFactor(0.8)
                        .widgetAccentable()
                    Spacer(minLength: 0)
                    answerArea(question)
                }
                .foregroundStyle(.white)
                .widgetSurface(Brand.dailyQuestion)
            } else {
                WidgetEmptyState(systemImage: "bubble.left.and.bubble.right.fill", message: "Today's question appears here", gradient: Brand.dailyQuestion)
            }
        }
        .widgetURL(URL(string: "twofold://home"))
    }

    @ViewBuilder
    private func answerArea(_ question: WidgetSnapshot.DailyQuestionInfo) -> some View {
        if !question.myAnswered {
            // Their answer, held back until you have given yours.
            HStack(spacing: 6) {
                if family != .systemSmall {
                    Capsule()
                        .fill(.white.opacity(0.35))
                        .frame(height: 14)
                        .frame(maxWidth: 120)
                        .blur(radius: 3)
                        .accessibilityHidden(true)
                }
                Label("Answer to see", systemImage: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
        } else if let answer = question.partnerAnswer {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.partnerName)
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(0.92)
                Text(answer)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(family == .systemSmall ? 2 : 3)
                    // Redacted on the Lock Screen and in StandBy while the phone is locked.
                    .privacySensitive()
            }
        } else {
            Label(question.partnerAnswered ? "Open to see their answer" : "Waiting for \(entry.partnerName)", systemImage: "hourglass")
                .font(.system(size: 12, weight: .semibold))
        }
    }
}

struct DailyQuestionWidget: Widget {
    let kind = "DailyQuestionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyQuestionProvider()) { entry in
            DailyQuestionWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily question")
        .description("Today's question, and your partner's answer once you've both answered.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemMedium) {
    DailyQuestionWidget()
} timeline: {
    DailyQuestionEntry(date: .now, question: WidgetSnapshot.DailyQuestionInfo(question: "What's a small thing I do that you love?", myAnswered: false, partnerAnswered: true, partnerAnswer: nil), partnerName: "Dara")
    DailyQuestionEntry(date: .now, question: WidgetSnapshot.DailyQuestionInfo(question: "What's a small thing I do that you love?", myAnswered: true, partnerAnswered: true, partnerAnswer: "The way you leave me notes in my suitcase."), partnerName: "Dara")
}

import SwiftUI
import WidgetKit

struct TodayWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: CalendarWidgetSnapshot
}

struct TodayWidgetProvider: TimelineProvider {
    private let store = CalendarWidgetSnapshotStore()
    private let timelinePolicy = CalendarWidgetTimelinePolicy()

    func placeholder(in context: Context) -> TodayWidgetEntry {
        TodayWidgetEntry(
            date: CalendarWidgetSnapshot.placeholder.generatedAt,
            snapshot: .placeholder
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWidgetEntry>) -> Void) {
        let currentEntry = entry()
        let nextUpdate = timelinePolicy.nextRefresh(after: Date())
        completion(
            Timeline(
                entries: [currentEntry],
                policy: .after(nextUpdate)
            )
        )
    }

    private func entry() -> TodayWidgetEntry {
        let snapshot = (try? store.load()) ?? .placeholder
        return TodayWidgetEntry(date: Date(), snapshot: snapshot)
    }
}

struct TodayWidgetEntryView: View {
    let entry: TodayWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("今天")
                    .font(.headline.weight(.semibold))
                Spacer(minLength: 4)
                Text(entry.snapshot.dateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.snapshot.statusLabel)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(statusColor)

                if let primaryTitle = entry.snapshot.primaryTitle {
                    Text(primaryTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }

            if entry.snapshot.scheduleCount > 0 {
                Label(
                    String(entry.snapshot.scheduleCount) + " 项本地日程",
                    systemImage: "calendar.badge.clock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let nextDate = entry.snapshot.nextDate {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Text("下一条重要日期")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(nextDate.dateLabel + "  " + nextDate.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    private var statusColor: Color {
        switch entry.snapshot.statusKey {
        case "holiday":
            .red
        case "makeupWorkday":
            .orange
        case "weekend":
            .secondary
        case "unknown":
            .gray
        default:
            .blue
        }
    }
}

struct TodayWidget: Widget {
    let kind = CalendarWidgetSnapshot.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayWidgetProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("今日概览")
        .description("查看今天状态和下一条重要日期。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview("Today Widget", as: .systemMedium) {
    TodayWidget()
} timeline: {
    TodayWidgetEntry(
        date: Date(),
        snapshot: CalendarWidgetSnapshot(
            generatedAt: Date(),
            dayID: "2026-08-11",
            dateLabel: "8月11日 周二",
            statusKey: "workday",
            statusLabel: "工作日",
            primaryTitle: "立秋",
            scheduleCount: 2,
            nextDate: CalendarWidgetNextDate(
                dayID: "2026-08-20",
                dateLabel: "8月20日 周四",
                title: "周末短途旅行",
                subtitle: "本地日程"
            )
        )
    )
}

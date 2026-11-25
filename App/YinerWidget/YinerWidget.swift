import SwiftUI
import WidgetKit
import YinerFocusCore

struct TodayEntry: TimelineEntry {
    let date: Date
    let count: Int
    let durationSeconds: Int
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), count: 0, durationSeconds: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = load()
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func load() -> TodayEntry {
        let now = Date()
        guard
            let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: YinerDefaults.appGroupIdentifier
            ),
            let payload = WidgetSummaryFile.load(from: WidgetSummaryFile.fileURL(in: container)),
            payload.day == dayStamp(now, timeZone: .current)
        else {
            return TodayEntry(date: now, count: 0, durationSeconds: 0)
        }
        return TodayEntry(date: now, count: payload.focusCount, durationSeconds: payload.focusDurationSeconds)
    }
}

struct TodayWidgetView: View {
    var entry: TodayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("今日专注")
                .font(.headline)
            Text("\(entry.count) 次")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text(formatHMS(entry.durationSeconds))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.yiner.focus.today", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("今日统计")
        .description("今天完成的专注场次和总时长。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct YinerWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}

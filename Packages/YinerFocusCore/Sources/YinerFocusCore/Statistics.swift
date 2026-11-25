import Foundation

public enum StatsScope: String, Codable, Equatable, Sendable, CaseIterable {
    case day
    case week
    case month
    case year

    public var name: String {
        switch self {
        case .day: return "日"
        case .week: return "周"
        case .month: return "月"
        case .year: return "年"
        }
    }
}

public enum StatsMetric: String, Codable, Equatable, Sendable, CaseIterable {
    case count
    case duration

    public var name: String {
        switch self {
        case .count: return "次数"
        case .duration: return "时长"
        }
    }
}

public struct StatsBucket: Equatable, Sendable, Identifiable {
    public var id: String
    public var start: Date
    public var label: String
    public var count: Int
    public var durationNetSeconds: Int

    public init(id: String, start: Date, label: String, count: Int, durationNetSeconds: Int) {
        self.id = id
        self.start = start
        self.label = label
        self.count = count
        self.durationNetSeconds = durationNetSeconds
    }
}

public struct StatsSummary: Equatable, Sendable {
    public var buckets: [StatsBucket]
    public var totalCount: Int
    public var totalDurationSeconds: Int

    public init(buckets: [StatsBucket], totalCount: Int, totalDurationSeconds: Int) {
        self.buckets = buckets
        self.totalCount = totalCount
        self.totalDurationSeconds = totalDurationSeconds
    }
}

public struct SessionQuery: Equatable, Sendable {
    /// nil 表示不按标签过滤。
    public var tag: String?
    public var includeIncomplete: Bool

    public init(tag: String? = nil, includeIncomplete: Bool = false) {
        self.tag = tag
        self.includeIncomplete = includeIncomplete
    }
}

public struct TodayWidgetPayload: Codable, Equatable, Sendable {
    public var day: String
    public var focusCount: Int
    public var focusDurationSeconds: Int
    public var updatedAt: Date

    public init(day: String, focusCount: Int, focusDurationSeconds: Int, updatedAt: Date) {
        self.day = day
        self.focusCount = focusCount
        self.focusDurationSeconds = focusDurationSeconds
        self.updatedAt = updatedAt
    }
}

public func makeCalendar(timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    calendar.locale = Locale(identifier: "zh_CN")
    calendar.firstWeekday = 2
    return calendar
}

public func periodRange(scope: StatsScope, anchor: Date, timeZone: TimeZone) -> DateInterval {
    let calendar = makeCalendar(timeZone: timeZone)
    switch scope {
    case .day:
        let start = calendar.startOfDay(for: anchor)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    case .week:
        let start = startOfWeek(anchor, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return DateInterval(start: start, end: end)
    case .month:
        let parts = calendar.dateComponents([.year, .month], from: anchor)
        let start = calendar.date(from: parts) ?? calendar.startOfDay(for: anchor)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    case .year:
        let year = calendar.component(.year, from: anchor)
        var parts = DateComponents()
        parts.year = year
        parts.month = 1
        parts.day = 1
        parts.timeZone = timeZone
        let start = calendar.date(from: parts) ?? anchor
        let end = calendar.date(byAdding: .year, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }
}

public func shifting(anchor: Date, scope: StatsScope, by steps: Int, timeZone: TimeZone) -> Date {
    let calendar = makeCalendar(timeZone: timeZone)
    switch scope {
    case .day:
        return calendar.date(byAdding: .day, value: steps, to: anchor) ?? anchor
    case .week:
        return calendar.date(byAdding: .day, value: steps * 7, to: anchor) ?? anchor
    case .month:
        return calendar.date(byAdding: .month, value: steps, to: anchor) ?? anchor
    case .year:
        return calendar.date(byAdding: .year, value: steps, to: anchor) ?? anchor
    }
}

public func isCurrentPeriod(scope: StatsScope, anchor: Date, now: Date, timeZone: TimeZone) -> Bool {
    let current = periodRange(scope: scope, anchor: now, timeZone: timeZone)
    let shown = periodRange(scope: scope, anchor: anchor, timeZone: timeZone)
    return current.start == shown.start
}

/// 已完成的场次按完成时间归桶，未完成的按开始时间。这样「今日完成」不会把跨日场次算错。
public func statsDate(of session: FocusSession) -> Date {
    if session.status == .completed, let completedAt = session.completedAt {
        return completedAt
    }
    return session.startedAt
}

public func focusSessionsForStats(
    stored: [FocusSession],
    active: FocusSession?,
    query: SessionQuery,
    range: DateInterval?
) -> [FocusSession] {
    var items = stored.filter { $0.kind == .focus }
    if let active, active.kind == .focus, !items.contains(where: { $0.id == active.id }) {
        items.append(active)
    }
    items = items.filter { session in
        if !session.status.isComplete && !query.includeIncomplete { return false }
        if let tag = query.tag, session.tag != tag { return false }
        if let range, !range.contains(statsDate(of: session)) { return false }
        return true
    }
    items.sort { statsDate(of: $0) > statsDate(of: $1) }
    return items
}

public func preservedSessions(_ sessions: [FocusSession]) -> [FocusSession] {
    sessions
        .filter { $0.kind == .preserved }
        .sorted { $0.startedAt > $1.startedAt }
}

public func aggregate(
    sessions: [FocusSession],
    scope: StatsScope,
    anchor: Date,
    timeZone: TimeZone
) -> StatsSummary {
    let calendar = makeCalendar(timeZone: timeZone)
    let slots = bucketSlots(scope: scope, anchor: anchor, calendar: calendar, timeZone: timeZone)
    var counts = Array(repeating: 0, count: slots.count)
    var durations = Array(repeating: 0, count: slots.count)
    for session in sessions where session.kind == .focus {
        let date = statsDate(of: session)
        guard let index = slots.firstIndex(where: { $0.range.contains(date) }) else { continue }
        counts[index] += 1
        durations[index] += max(0, session.durationNetSeconds)
    }
    let buckets = zip(slots.indices, slots).map { index, slot in
        StatsBucket(
            id: "\(scope.rawValue)-\(slot.range.start.timeIntervalSince1970)",
            start: slot.range.start,
            label: slot.label,
            count: counts[index],
            durationNetSeconds: durations[index]
        )
    }
    return StatsSummary(
        buckets: buckets,
        totalCount: counts.reduce(0, +),
        totalDurationSeconds: durations.reduce(0, +)
    )
}

public func todaySummary(sessions: [FocusSession], now: Date, timeZone: TimeZone) -> TodayWidgetPayload {
    let range = periodRange(scope: .day, anchor: now, timeZone: timeZone)
    let todays = sessions.filter { session in
        guard session.kind == .focus, session.status == .completed, let completedAt = session.completedAt else {
            return false
        }
        return range.contains(completedAt)
    }
    return TodayWidgetPayload(
        day: dayStamp(now, timeZone: timeZone),
        focusCount: todays.count,
        focusDurationSeconds: todays.reduce(0) { $0 + $1.durationNetSeconds },
        updatedAt: now
    )
}

public func dayStamp(_ date: Date, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

private struct BucketSlot {
    var range: DateInterval
    var label: String
}

private func bucketSlots(
    scope: StatsScope,
    anchor: Date,
    calendar: Calendar,
    timeZone: TimeZone
) -> [BucketSlot] {
    switch scope {
    case .day:
        let start = calendar.startOfDay(for: anchor)
        return (0..<24).map { hour in
            let slotStart = calendar.date(byAdding: .hour, value: hour, to: start) ?? start
            let slotEnd = calendar.date(byAdding: .hour, value: 1, to: slotStart) ?? slotStart
            return BucketSlot(range: DateInterval(start: slotStart, end: slotEnd), label: "\(hour)")
        }
    case .week:
        let names = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        let start = startOfWeek(anchor, calendar: calendar)
        return (0..<7).map { offset in
            let slotStart = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            let slotEnd = calendar.date(byAdding: .day, value: 1, to: slotStart) ?? slotStart
            return BucketSlot(range: DateInterval(start: slotStart, end: slotEnd), label: names[offset])
        }
    case .month:
        let range = periodRange(scope: .month, anchor: anchor, timeZone: timeZone)
        let dayCount = calendar.range(of: .day, in: .month, for: range.start)?.count ?? 30
        return (0..<dayCount).map { offset in
            let slotStart = calendar.date(byAdding: .day, value: offset, to: range.start) ?? range.start
            let slotEnd = calendar.date(byAdding: .day, value: 1, to: slotStart) ?? slotStart
            let day = calendar.component(.day, from: slotStart)
            return BucketSlot(range: DateInterval(start: slotStart, end: slotEnd), label: "\(day)")
        }
    case .year:
        let year = calendar.component(.year, from: anchor)
        return (1...12).map { month in
            var parts = DateComponents()
            parts.year = year
            parts.month = month
            parts.day = 1
            parts.timeZone = timeZone
            let slotStart = calendar.date(from: parts) ?? anchor
            let slotEnd = calendar.date(byAdding: .month, value: 1, to: slotStart) ?? slotStart
            return BucketSlot(range: DateInterval(start: slotStart, end: slotEnd), label: "\(month)月")
        }
    }
}

private func startOfWeek(_ anchor: Date, calendar: Calendar) -> Date {
    let day = calendar.startOfDay(for: anchor)
    let weekday = calendar.component(.weekday, from: day)
    let mondayOffset = (weekday + 5) % 7
    return calendar.date(byAdding: .day, value: -mondayOffset, to: day) ?? day
}

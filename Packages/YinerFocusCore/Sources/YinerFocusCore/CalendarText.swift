import Foundation

public struct CalendarEventDraft: Equatable, Sendable {
    public var title: String
    public var notes: String
    public var start: Date
    public var end: Date

    public init(title: String, notes: String, start: Date, end: Date) {
        self.title = title
        self.notes = notes
        self.start = start
        self.end = end
    }
}

public enum CalendarText {
    /// 只为已完成的专注生成事件。休息不写日历。
    /// 备注固定两行：净时长，以及含中断。标题和标签都有时，标签附在第二行。
    public static func draft(for session: FocusSession) -> CalendarEventDraft? {
        guard session.kind == .focus, session.status == .completed, let end = session.completedAt else {
            return nil
        }
        guard end > session.startedAt else { return nil }
        let title = eventTitle(title: session.title, tag: session.tag)
        var second = "含中断 \(formatHMS(session.durationGrossSeconds))"
        if !session.title.isEmpty && !session.tag.isEmpty {
            second += "（\(session.tag)）"
        }
        let notes = "净时长 \(formatHMS(session.durationNetSeconds))\n\(second)"
        return CalendarEventDraft(title: title, notes: notes, start: session.startedAt, end: end)
    }

    public static func eventTitle(title: String, tag: String) -> String {
        if !title.isEmpty { return title }
        if !tag.isEmpty {
            return YinerDefaults.defaultFocusTitle + YinerDefaults.calendarTitleSeparator + tag
        }
        return YinerDefaults.defaultFocusTitle
    }
}

import Foundation

public enum WallTime {
    public static func format(date: Date, timeZone: TimeZone) -> String {
        let formatter = makeFormatter(timeZone: timeZone)
        return formatter.string(from: date)
    }

    public static func parse(_ text: String, timeZone: TimeZone) -> Date? {
        let formatter = makeFormatter(timeZone: timeZone)
        return formatter.date(from: text)
    }

    private static func makeFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.isLenient = false
        return formatter
    }
}

/// CSV 与日历备注用的 `HH:MM:SS`。小时至少两位，超过 99 不截断。
public func formatHMS(_ seconds: Int) -> String {
    let total = max(0, seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return String(format: "%02d:%02d:%02d", hours, minutes, secs)
}

public func parseHMS(_ text: String) -> Int? {
    let parts = text.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 3,
          let hours = Int(parts[0]),
          let minutes = Int(parts[1]),
          let seconds = Int(parts[2]),
          hours >= 0,
          (0...59).contains(minutes),
          (0...59).contains(seconds)
    else { return nil }
    return hours * 3600 + minutes * 60 + seconds
}

/// 菜单栏倒计时。不到 1 小时显示 `分:秒`，否则显示 `时:分:秒`。
public func formatClock(_ seconds: Int) -> String {
    let total = max(0, seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}

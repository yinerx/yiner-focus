import Foundation

public enum SessionPhase: String, Codable, Equatable, Sendable {
    case focus
    case shortBreak
    case longBreak

    public var name: String {
        switch self {
        case .focus: return "专注"
        case .shortBreak: return "短休息"
        case .longBreak: return "长休息"
        }
    }
}

public enum RunState: String, Codable, Equatable, Sendable {
    case idle
    case running
    case paused

    public var name: String {
        switch self {
        case .idle: return "待开始"
        case .running: return "进行中"
        case .paused: return "已暂停"
        }
    }
}

public enum SessionKind: String, Codable, Equatable, Sendable {
    case focus
    case shortBreak
    case longBreak
    /// CSV 里出现了样例以外的 Type。原样留着，方便再导出。
    case preserved

    public var name: String {
        switch self {
        case .focus: return "专注"
        case .shortBreak: return "短休息"
        case .longBreak: return "长休息"
        case .preserved: return "其他"
        }
    }
}

public enum SessionStatus: String, Codable, Equatable, Sendable {
    case inProgress
    case paused
    case completed
    case incomplete

    public var name: String {
        switch self {
        case .inProgress: return "进行中"
        case .paused: return "已暂停"
        case .completed: return "已完成"
        case .incomplete: return "未完成"
        }
    }

    public var isComplete: Bool { self == .completed }
}

public struct FocusSession: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: SessionKind
    public var typeRaw: String
    public var title: String
    public var tag: String
    public var durationNetSeconds: Int
    public var durationGrossSeconds: Int
    public var startedAt: Date
    public var completedAt: Date?
    public var status: SessionStatus
    public var cycleLengthSnapshot: Int?

    public init(
        id: String,
        kind: SessionKind,
        typeRaw: String,
        title: String,
        tag: String,
        durationNetSeconds: Int,
        durationGrossSeconds: Int,
        startedAt: Date,
        completedAt: Date?,
        status: SessionStatus,
        cycleLengthSnapshot: Int?
    ) {
        self.id = id
        self.kind = kind
        self.typeRaw = typeRaw
        self.title = title
        self.tag = tag
        self.durationNetSeconds = durationNetSeconds
        self.durationGrossSeconds = durationGrossSeconds
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.status = status
        self.cycleLengthSnapshot = cycleLengthSnapshot
    }
}

public enum Appearance: String, Codable, Equatable, Sendable, CaseIterable {
    case system
    case light
    case dark

    public var name: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

public enum WebListMode: String, Codable, Equatable, Sendable {
    case block
    case allow

    public var name: String {
        switch self {
        case .block: return "阻止"
        case .allow: return "允许"
        }
    }
}

public enum KnownBrowser: String, Codable, Equatable, Sendable, CaseIterable, Identifiable {
    case safari
    case chrome
    case arc

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .safari: return "Safari"
        case .chrome: return "Google Chrome"
        case .arc: return "Arc"
        }
    }

    /// 系统用来判断进程是否已打开，避免脚本把没开的浏览器拉起来。
    public var bundleIdentifier: String {
        switch self {
        case .safari: return "com.apple.Safari"
        case .chrome: return "com.google.Chrome"
        case .arc: return "company.thebrowser.Browser"
        }
    }

    /// AppleScript 里 `tell application` 使用的公开名称。
    public var appleScriptName: String {
        switch self {
        case .safari: return "Safari"
        case .chrome: return "Google Chrome"
        case .arc: return "Arc"
        }
    }
}

public struct FocusSettings: Codable, Equatable, Sendable {
    public var focusMinutes: Int
    public var shortBreakMinutes: Int
    public var longBreakMinutes: Int
    public var cycleLength: Int
    public var autoStartBreak: Bool
    public var autoStartFocus: Bool
    public var notifyFocusEnd: Bool
    public var notifyBreakEnd: Bool
    public var launchAtLogin: Bool
    public var showPopoverAtLaunch: Bool
    public var resetCycleAtLaunch: Bool
    public var startFocusAtLaunch: Bool
    public var hidePopoverWhenRunning: Bool
    public var windowAlwaysOnTop: Bool
    public var appearance: Appearance
    public var calendarSyncEnabled: Bool
    public var calendarIdentifier: String?
    public var webMode: WebListMode
    public var enabledBrowsers: [KnownBrowser]
    public var globalHotkeyEnabled: Bool

    public init(
        focusMinutes: Int = YinerDefaults.focusMinutes,
        shortBreakMinutes: Int = YinerDefaults.shortBreakMinutes,
        longBreakMinutes: Int = YinerDefaults.longBreakMinutes,
        cycleLength: Int = YinerDefaults.cycleLength,
        autoStartBreak: Bool = YinerDefaults.autoStartBreak,
        autoStartFocus: Bool = YinerDefaults.autoStartFocus,
        notifyFocusEnd: Bool = YinerDefaults.notifyFocusEnd,
        notifyBreakEnd: Bool = YinerDefaults.notifyBreakEnd,
        launchAtLogin: Bool = YinerDefaults.launchAtLogin,
        showPopoverAtLaunch: Bool = YinerDefaults.showPopoverAtLaunch,
        resetCycleAtLaunch: Bool = YinerDefaults.resetCycleAtLaunch,
        startFocusAtLaunch: Bool = YinerDefaults.startFocusAtLaunch,
        hidePopoverWhenRunning: Bool = YinerDefaults.hidePopoverWhenRunning,
        windowAlwaysOnTop: Bool = YinerDefaults.windowAlwaysOnTop,
        appearance: Appearance = .system,
        calendarSyncEnabled: Bool = YinerDefaults.calendarSyncEnabled,
        calendarIdentifier: String? = nil,
        webMode: WebListMode = YinerDefaults.webModeIsAllow ? .allow : .block,
        enabledBrowsers: [KnownBrowser] = KnownBrowser.allCases,
        globalHotkeyEnabled: Bool = YinerDefaults.globalHotkeyEnabled
    ) {
        self.focusMinutes = focusMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.cycleLength = cycleLength
        self.autoStartBreak = autoStartBreak
        self.autoStartFocus = autoStartFocus
        self.notifyFocusEnd = notifyFocusEnd
        self.notifyBreakEnd = notifyBreakEnd
        self.launchAtLogin = launchAtLogin
        self.showPopoverAtLaunch = showPopoverAtLaunch
        self.resetCycleAtLaunch = resetCycleAtLaunch
        self.startFocusAtLaunch = startFocusAtLaunch
        self.hidePopoverWhenRunning = hidePopoverWhenRunning
        self.windowAlwaysOnTop = windowAlwaysOnTop
        self.appearance = appearance
        self.calendarSyncEnabled = calendarSyncEnabled
        self.calendarIdentifier = calendarIdentifier
        self.webMode = webMode
        self.enabledBrowsers = enabledBrowsers
        self.globalHotkeyEnabled = globalHotkeyEnabled
    }

    public static let standard = FocusSettings()

    public func clamped() -> FocusSettings {
        var copy = self
        copy.focusMinutes = YinerDefaults.clampedDuration(focusMinutes)
        copy.shortBreakMinutes = YinerDefaults.clampedDuration(shortBreakMinutes)
        copy.longBreakMinutes = YinerDefaults.clampedDuration(longBreakMinutes)
        copy.cycleLength = YinerDefaults.clampedCycle(cycleLength)
        if !YinerDefaults.allowsCustomDuration {
            if !YinerDefaults.focusPresetMinutes.contains(copy.focusMinutes) {
                copy.focusMinutes = YinerDefaults.focusMinutes
            }
            if !YinerDefaults.shortBreakPresetMinutes.contains(copy.shortBreakMinutes) {
                copy.shortBreakMinutes = YinerDefaults.shortBreakMinutes
            }
            if !YinerDefaults.longBreakPresetMinutes.contains(copy.longBreakMinutes) {
                copy.longBreakMinutes = YinerDefaults.longBreakMinutes
            }
        }
        copy.globalHotkeyEnabled = false
        return copy
    }
}

public struct FocusTag: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var colorHex: String
    public var sortIndex: Int

    public init(id: String, name: String, colorHex: String, sortIndex: Int) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sortIndex = sortIndex
    }
}

public struct WebRule: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var pattern: String

    public init(id: String = UUID().uuidString, pattern: String) {
        self.id = id
        self.pattern = pattern
    }
}

public struct AppRule: Codable, Equatable, Sendable, Identifiable {
    public var bundleID: String
    public var displayName: String
    public var id: String { bundleID }

    public init(bundleID: String, displayName: String) {
        self.bundleID = bundleID
        self.displayName = displayName
    }
}

public enum ManualEntry {
    /// 补记一场已完成的专注。结束不晚于开始时返回 nil。净时长与墙钟跨度相同。
    public static func completedFocus(
        title: String,
        tag: String,
        startedAt: Date,
        completedAt: Date,
        cycleLength: Int
    ) -> FocusSession? {
        let gross = Int(completedAt.timeIntervalSince(startedAt).rounded(.down))
        guard gross > 0 else { return nil }
        return FocusSession(
            id: UUID().uuidString,
            kind: .focus,
            typeRaw: YinerDefaults.exportedFocusType,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            tag: tag.trimmingCharacters(in: .whitespacesAndNewlines),
            durationNetSeconds: gross,
            durationGrossSeconds: gross,
            startedAt: startedAt,
            completedAt: completedAt,
            status: .completed,
            cycleLengthSnapshot: cycleLength
        )
    }
}

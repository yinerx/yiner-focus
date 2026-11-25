import Foundation

/// 待确认项的默认值，以及其它想改一处就全局生效的常量。
/// 银耳确认之前按 docs/spec.md 第 10 节的默认实现，不要散落到各处。
public enum YinerDefaults {
    // MARK: 待确认 1 — 名称与 Bundle ID
    public static let appName = "银耳专注"
    public static let bundleIdentifier = "com.yiner.focus"
    public static let appGroupIdentifier = "group.com.yiner.focus"
    public static let marketingVersion = "0.1.0"

    // MARK: 待确认 2 — 第三个浏览器
    /// 名称未确认，不接入真实进程。界面只显示这一行占位。
    public static let pendingBrowserTitle = "待确认的第三个浏览器（Cra）"

    // MARK: 待确认 3 — 日历文案
    public static let defaultFocusTitle = "专注"
    public static let calendarTitleSeparator = " · "

    // MARK: 待确认 4 — 小组件
    /// 默认做「今日统计」。若以后确认不做，删掉 App 工程里的小组件目标即可。
    public static let includesTodayWidget = true

    // MARK: 待确认 5 — 自定义时长
    public static let allowsCustomDuration = true
    public static let durationMinuteRange = 1...90
    public static let focusPresetMinutes = [15, 20, 25, 30, 45, 50, 60, 90]
    public static let shortBreakPresetMinutes = [5, 10]
    public static let longBreakPresetMinutes = [15, 20, 30]
    public static let focusMinutes = 25
    public static let shortBreakMinutes = 5
    public static let longBreakMinutes = 30
    public static let cycleLength = 4
    public static let cycleLengthRange = 1...10

    // MARK: 待确认 6 — 全局快捷键
    /// 入口保留，但按键未确认，不能真正启用。
    public static let globalHotkeyEnabled = false

    // MARK: 待确认 7 — 休息是否写入 CSV
    /// 关闭时只导出已完成的专注，Type 写 Flow。未知 Type 仍原样导出，方便往返。
    public static let exportBreaks = false
    public static let exportedFocusType = "Flow"
    public static let storedShortBreakType = "ShortBreak"
    public static let storedLongBreakType = "LongBreak"
    public static let csvHeader = "Type,Title,Tag,Duration,Duration With Interruptions,Started,Completed,ID"

    // MARK: 待确认 8 — 登录时启动
    public static let launchAtLogin = true
    /// 需求没有写明这三项的默认。菜单栏应用不在登录时抢焦点，也不自动清周期、不自动开始。
    public static let showPopoverAtLaunch = false
    public static let resetCycleAtLaunch = false
    public static let startFocusAtLaunch = false

    // MARK: 待确认 9 — 窗口
    public static let hidePopoverWhenRunning = true
    public static let windowAlwaysOnTop = false

    // MARK: 其它默认（需求写了行为，没单独列为待确认）
    public static let autoStartBreak = false
    public static let autoStartFocus = false
    public static let notifyFocusEnd = true
    public static let notifyBreakEnd = true
    public static let webModeIsAllow = false
    public static let calendarSyncEnabled = false

    /// 轮询间隔。打开被拦网站后，大约在这个量级内换成拦截页。实际延迟要在 Mac 上量。
    public static let blockPollSeconds: TimeInterval = 0.5
    public static let blockScriptTimeoutSeconds: TimeInterval = 2
    public static let menuBarTickSeconds: TimeInterval = 1

    /// 精确规则：去掉开头的一个 `*`，再与完整 URL 做不区分大小写的比较。
    /// 比较前双方各去掉末尾至多一个 `/`，因此带不带末尾斜线视为同一地址。
    /// 查询串、更长的路径、协议或子域不同，都不匹配。
    public static let exactRulePrefix: Character = "*"
    public static let blockPageFileName = "YinerBlock.html"

    /// 连续把被拦截应用退到后台时，若 1 秒内超过这个次数就先停手，避免两个被拦应用互相抢前台。
    public static let appHideBurstLimit = 3
    public static let appHideBurstWindowSeconds: TimeInterval = 1

    public static let storeFolderName = "YinerFocus"
    public static let storeFileName = "store.json"
    public static let widgetFileName = "widget-summary.json"

    public static let defaultTags: [(name: String, colorHex: String)] = [
        ("工作", "#B5523A"),
        ("个人", "#3E6D8C"),
        ("学习", "#C4892F")
    ]
    public static let extraTagColors = ["#6E5A7D", "#3F6F5B", "#8A5A44", "#4E5E78"]

    public static func clampedDuration(_ minutes: Int) -> Int {
        min(max(minutes, durationMinuteRange.lowerBound), durationMinuteRange.upperBound)
    }

    public static func clampedCycle(_ length: Int) -> Int {
        min(max(length, cycleLengthRange.lowerBound), cycleLengthRange.upperBound)
    }
}

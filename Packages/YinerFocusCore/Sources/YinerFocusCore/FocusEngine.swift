import Foundation

public struct MenuBarLabel: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        case focusRunning
        case focusPaused
        case focusIdle
        case breakRunning
        case breakPaused
        case breakIdle
    }

    public var style: Style
    public var text: String

    public init(style: Style, text: String) {
        self.style = style
        self.text = text
    }
}

public struct PhaseCompletion: Equatable, Sendable {
    public var session: FocusSession
    public var shouldNotify: Bool
    public var finishedPhase: SessionPhase

    public init(session: FocusSession, shouldNotify: Bool, finishedPhase: SessionPhase) {
        self.session = session
        self.shouldNotify = shouldNotify
        self.finishedPhase = finishedPhase
    }
}

/// 专注 / 短休息 / 长休息的倒计时。时间全部由调用方传入，方便测试，也不在库里开定时器。
public struct FocusEngine: Codable, Equatable, Sendable {
    public var settings: FocusSettings
    public var phase: SessionPhase
    public var runState: RunState
    public var focusIndex: Int
    public var title: String
    public var tag: String?
    public internal(set) var remainingSeconds: Int
    public internal(set) var plannedSeconds: Int
    public internal(set) var segmentStartedAt: Date?
    public internal(set) var runningSince: Date?
    public internal(set) var pauseStartedAt: Date?
    public internal(set) var accumulatedPauseSeconds: Int
    public internal(set) var activeID: String?

    public init(settings: FocusSettings = .standard, now: Date = Date()) {
        let clamped = settings.clamped()
        self.settings = clamped
        self.phase = .focus
        self.runState = .idle
        self.focusIndex = 1
        self.title = ""
        self.tag = nil
        let planned = clamped.focusMinutes * 60
        self.plannedSeconds = planned
        self.remainingSeconds = planned
        self.segmentStartedAt = nil
        self.runningSince = nil
        self.pauseStartedAt = nil
        self.accumulatedPauseSeconds = 0
        self.activeID = nil
        _ = now
    }

    public var phaseName: String { phase.name }
    public var runStateName: String { runState.name }
    public var progressText: String { "第 \(focusIndex) 次，共 \(settings.cycleLength) 次" }
    public var primaryButtonTitle: String { runState == .running ? "暂停" : "开始" }
    public var canSkipBreak: Bool { phase != .focus }

    /// 已经在周期开头、待开始、还没计过时，重置没有意义。
    public var canReset: Bool {
        if phase == .focus, focusIndex == 1, runState == .idle, segmentStartedAt == nil {
            return false
        }
        return true
    }

    public func remaining(at now: Date) -> Int {
        guard runState == .running, let runningSince else { return remainingSeconds }
        let elapsed = max(0, Int(now.timeIntervalSince(runningSince).rounded(.down)))
        return max(0, remainingSeconds - elapsed)
    }

    public func menuBarLabel(at now: Date) -> MenuBarLabel {
        let clock = formatClock(remaining(at: now))
        let onBreak = phase != .focus
        switch runState {
        case .running:
            return MenuBarLabel(
                style: onBreak ? .breakRunning : .focusRunning,
                text: "● \(clock)"
            )
        case .paused:
            return MenuBarLabel(
                style: onBreak ? .breakPaused : .focusPaused,
                text: "暂停 \(clock)"
            )
        case .idle:
            return MenuBarLabel(
                style: onBreak ? .breakIdle : .focusIdle,
                text: "○ \(phaseName)"
            )
        }
    }

    public mutating func start(now: Date) {
        switch runState {
        case .running:
            return
        case .paused:
            if let pauseStartedAt {
                let extra = max(0, Int(now.timeIntervalSince(pauseStartedAt).rounded(.down)))
                accumulatedPauseSeconds += extra
            }
            pauseStartedAt = nil
            runningSince = now
            runState = .running
        case .idle:
            segmentStartedAt = now
            runningSince = now
            pauseStartedAt = nil
            accumulatedPauseSeconds = 0
            remainingSeconds = plannedSeconds
            activeID = UUID().uuidString
            runState = .running
        }
    }

    public mutating func pause(now: Date) {
        guard runState == .running else { return }
        remainingSeconds = remaining(at: now)
        runningSince = nil
        pauseStartedAt = now
        runState = .paused
    }

    public mutating func toggle(now: Date) {
        if runState == .running {
            pause(now: now)
        } else {
            start(now: now)
        }
    }

    /// 跳过当前休息，进入下一场专注。默认停在待开始；只有「休息结束后自动开始专注」打开时才直接计时。
    public mutating func skipBreak(now: Date) {
        guard phase != .focus else { return }
        switch phase {
        case .shortBreak:
            focusIndex = min(focusIndex + 1, max(settings.cycleLength, 1))
            phase = .focus
        case .longBreak:
            focusIndex = 1
            phase = .focus
        case .focus:
            break
        }
        openPhase(at: now, autoStart: settings.autoStartFocus)
    }

    /// 回到第 1 次专注、待开始，绝不自动开始。进行中的专注会记成未完成。
    public mutating func resetCycle(now: Date) -> FocusSession? {
        let partial = abandonedFocus(now: now)
        focusIndex = 1
        phase = .focus
        title = ""
        openPhase(at: now, autoStart: false)
        return partial
    }

    public mutating func updateSettings(_ newSettings: FocusSettings, now: Date) {
        settings = newSettings.clamped()
        if focusIndex > settings.cycleLength {
            focusIndex = settings.cycleLength
        }
        if focusIndex < 1 {
            focusIndex = 1
        }
        plannedSeconds = durationSeconds(for: phase)
        if runState == .idle {
            remainingSeconds = plannedSeconds
        }
        _ = now
    }

    /// 进行中才会往前走。一次调用可以跨过多个阶段（例如合上盖子很久），自动开始关闭时最多完成当前这一段。
    public mutating func tick(now: Date) -> [PhaseCompletion] {
        var result: [PhaseCompletion] = []
        var safety = 0
        while runState == .running, safety < 16 {
            safety += 1
            guard let since = runningSince else { break }
            let elapsed = max(0, Int(now.timeIntervalSince(since).rounded(.down)))
            if elapsed < remainingSeconds { break }
            let end = since.addingTimeInterval(TimeInterval(remainingSeconds))
            result.append(finishPhase(at: end))
        }
        return result
    }

    /// 已经开始、还没完成的这一段。统计页打开「显示未完成」时用它。
    public func activeSession(at now: Date) -> FocusSession? {
        guard runState != .idle, let accounting = elapsedAccounting(at: now) else { return nil }
        let status: SessionStatus = runState == .paused ? .paused : .inProgress
        return makeSession(
            started: accounting.started,
            ended: nil,
            net: accounting.net,
            gross: accounting.gross,
            status: status
        )
    }

    private mutating func abandonedFocus(now: Date) -> FocusSession? {
        guard phase == .focus, runState != .idle, let accounting = elapsedAccounting(at: now) else {
            return nil
        }
        if accounting.net == 0 && accounting.gross == 0 { return nil }
        return makeSession(
            started: accounting.started,
            ended: now,
            net: accounting.net,
            gross: accounting.gross,
            status: .incomplete
        )
    }

    private func elapsedAccounting(at now: Date) -> (started: Date, net: Int, gross: Int)? {
        guard let started = segmentStartedAt, runState != .idle else { return nil }
        var pause = accumulatedPauseSeconds
        if runState == .paused, let pauseStartedAt {
            pause += max(0, Int(now.timeIntervalSince(pauseStartedAt).rounded(.down)))
        }
        let gross = max(0, Int(now.timeIntervalSince(started).rounded(.down)))
        let net = max(0, gross - pause)
        return (started, net, gross)
    }

    private mutating func finishPhase(at end: Date) -> PhaseCompletion {
        let started = segmentStartedAt ?? end
        let gross = max(0, Int(end.timeIntervalSince(started).rounded()))
        let net = max(0, gross - accumulatedPauseSeconds)
        let session = makeSession(
            started: started,
            ended: end,
            net: net,
            gross: gross,
            status: .completed
        )
        let notify: Bool
        switch phase {
        case .focus:
            notify = settings.notifyFocusEnd
            title = ""
        case .shortBreak, .longBreak:
            notify = settings.notifyBreakEnd
        }
        let finished = phase
        moveToNextPhase(at: end)
        return PhaseCompletion(session: session, shouldNotify: notify, finishedPhase: finished)
    }

    private func makeSession(
        started: Date,
        ended: Date?,
        net: Int,
        gross: Int,
        status: SessionStatus
    ) -> FocusSession {
        let kind = SessionKind(phase: phase)
        return FocusSession(
            id: activeID ?? UUID().uuidString,
            kind: kind,
            typeRaw: kind.storedTypeRaw,
            title: title,
            tag: tag ?? "",
            durationNetSeconds: net,
            durationGrossSeconds: gross,
            startedAt: started,
            completedAt: ended,
            status: status,
            cycleLengthSnapshot: settings.cycleLength
        )
    }

    private mutating func moveToNextPhase(at now: Date) {
        switch phase {
        case .focus:
            phase = focusIndex >= settings.cycleLength ? .longBreak : .shortBreak
            openPhase(at: now, autoStart: settings.autoStartBreak)
        case .shortBreak:
            focusIndex = min(focusIndex + 1, max(settings.cycleLength, 1))
            phase = .focus
            openPhase(at: now, autoStart: settings.autoStartFocus)
        case .longBreak:
            focusIndex = 1
            phase = .focus
            openPhase(at: now, autoStart: settings.autoStartFocus)
        }
    }

    private mutating func openPhase(at now: Date, autoStart: Bool) {
        plannedSeconds = durationSeconds(for: phase)
        remainingSeconds = plannedSeconds
        accumulatedPauseSeconds = 0
        pauseStartedAt = nil
        if autoStart {
            runState = .running
            segmentStartedAt = now
            runningSince = now
            activeID = UUID().uuidString
        } else {
            runState = .idle
            segmentStartedAt = nil
            runningSince = nil
            activeID = nil
        }
    }

    private func durationSeconds(for phase: SessionPhase) -> Int {
        let minutes: Int
        switch phase {
        case .focus: minutes = settings.focusMinutes
        case .shortBreak: minutes = settings.shortBreakMinutes
        case .longBreak: minutes = settings.longBreakMinutes
        }
        return minutes * 60
    }
}

private extension SessionKind {
    init(phase: SessionPhase) {
        switch phase {
        case .focus: self = .focus
        case .shortBreak: self = .shortBreak
        case .longBreak: self = .longBreak
        }
    }

    var storedTypeRaw: String {
        switch self {
        case .focus: return YinerDefaults.exportedFocusType
        case .shortBreak: return YinerDefaults.storedShortBreakType
        case .longBreak: return YinerDefaults.storedLongBreakType
        case .preserved: return ""
        }
    }
}

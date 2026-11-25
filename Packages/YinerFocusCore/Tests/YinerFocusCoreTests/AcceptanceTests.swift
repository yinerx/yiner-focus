import XCTest
@testable import YinerFocusCore

final class AcceptanceTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    func testA01_defaultCycleReachesLongBreakAfterFourFocuses() {
        var engine = FocusEngine(settings: .standard, now: origin)
        var now = origin
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.focusIndex, 1)
        XCTAssertEqual(engine.runState, .idle)
        XCTAssertEqual(engine.settings.cycleLength, 4)

        for index in 1...4 {
            XCTAssertEqual(engine.phase, .focus)
            XCTAssertEqual(engine.focusIndex, index)
            let done = finishCurrent(&engine, now: &now)
            XCTAssertEqual(done.finishedPhase, .focus)
            if index < 4 {
                XCTAssertEqual(engine.phase, .shortBreak)
                XCTAssertEqual(engine.runState, .idle)
                _ = finishCurrent(&engine, now: &now)
            } else {
                XCTAssertEqual(engine.phase, .longBreak)
                XCTAssertEqual(engine.runState, .idle)
            }
        }
    }

    func testA02_presetsApplyToTheNextIdlePhase() {
        XCTAssertEqual(YinerDefaults.focusPresetMinutes, [15, 20, 25, 30, 45, 50, 60, 90])
        XCTAssertEqual(YinerDefaults.shortBreakPresetMinutes, [5, 10])
        XCTAssertEqual(YinerDefaults.longBreakPresetMinutes, [15, 20, 30])

        var engine = FocusEngine(settings: .standard, now: origin)
        var now = origin
        XCTAssertEqual(engine.remaining(at: now), 25 * 60)
        XCTAssertEqual(engine.settings.shortBreakMinutes, 5)
        XCTAssertEqual(engine.settings.longBreakMinutes, 30)

        var settings = engine.settings
        settings.focusMinutes = 45
        engine.updateSettings(settings, now: now)
        XCTAssertEqual(engine.runState, .idle)
        XCTAssertEqual(engine.remaining(at: now), 45 * 60)

        engine.start(now: now)
        settings.focusMinutes = 15
        settings.shortBreakMinutes = 10
        settings.longBreakMinutes = 15
        engine.updateSettings(settings, now: now)
        XCTAssertEqual(engine.remaining(at: now), 45 * 60)

        now = now.addingTimeInterval(TimeInterval(engine.remaining(at: now)))
        _ = engine.tick(now: now)
        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertEqual(engine.runState, .idle)
        XCTAssertEqual(engine.remaining(at: now), 10 * 60)

        _ = finishCurrent(&engine, now: &now)
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.runState, .idle)
        XCTAssertEqual(engine.remaining(at: now), 15 * 60)
    }

    func testA03_pauseFreezesRemainingAndResumeContinues() {
        var engine = FocusEngine(settings: .standard, now: origin)
        var now = origin
        engine.start(now: now)
        now = now.addingTimeInterval(20)
        let left = engine.remaining(at: now)
        engine.pause(now: now)
        XCTAssertEqual(engine.runState, .paused)
        XCTAssertEqual(engine.remaining(at: now), left)
        now = now.addingTimeInterval(30)
        XCTAssertEqual(engine.remaining(at: now), left)
        engine.start(now: now)
        XCTAssertEqual(engine.runState, .running)
        XCTAssertEqual(engine.remaining(at: now), left)
        XCTAssertNotEqual(left, 25 * 60)
    }

    func testA04_skipBreakMovesToTheNextFocus() {
        var engine = FocusEngine(settings: .standard, now: origin)
        var now = origin
        _ = finishCurrent(&engine, now: &now)
        XCTAssertEqual(engine.phase, .shortBreak)
        engine.skipBreak(now: now)
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.focusIndex, 2)
        XCTAssertEqual(engine.runState, .idle)

        var longBreak = FocusEngine(settings: .standard, now: origin)
        var clock = origin
        for _ in 1...4 {
            _ = finishCurrent(&longBreak, now: &clock)
            if longBreak.phase == .shortBreak {
                _ = finishCurrent(&longBreak, now: &clock)
            }
        }
        XCTAssertEqual(longBreak.phase, .longBreak)
        longBreak.skipBreak(now: clock)
        XCTAssertEqual(longBreak.phase, .focus)
        XCTAssertEqual(longBreak.focusIndex, 1)
        XCTAssertEqual(longBreak.runState, .idle)
    }

    func testA05_resetReturnsToFirstFocusAndDoesNotAutoStart() {
        var settings = FocusSettings.standard
        settings.autoStartBreak = true
        settings.autoStartFocus = true
        var engine = FocusEngine(settings: settings, now: origin)
        var now = origin
        XCTAssertFalse(engine.canReset)
        engine.start(now: now)
        now = now.addingTimeInterval(TimeInterval(engine.remaining(at: now)))
        _ = engine.tick(now: now)
        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertEqual(engine.runState, .running)
        XCTAssertTrue(engine.canReset)

        _ = engine.resetCycle(now: now)
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.focusIndex, 1)
        XCTAssertEqual(engine.runState, .idle)
        XCTAssertFalse(engine.canReset)
        let later = now.addingTimeInterval(5)
        XCTAssertTrue(engine.tick(now: later).isEmpty)
        XCTAssertEqual(engine.runState, .idle)
    }

    func testA06_withoutAutoStartFocusEndsInAnIdleShortBreak() {
        var engine = FocusEngine(settings: .standard, now: origin)
        var now = origin
        XCTAssertFalse(engine.settings.autoStartBreak)
        XCTAssertFalse(engine.settings.autoStartFocus)
        _ = finishCurrent(&engine, now: &now)
        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertEqual(engine.runState, .idle)
        XCTAssertTrue(engine.tick(now: now.addingTimeInterval(3)).isEmpty)
        XCTAssertEqual(engine.runState, .idle)
    }

    func testA07_autoStartBeginsTheNextPhase() {
        var settings = FocusSettings.standard
        settings.autoStartBreak = true
        settings.autoStartFocus = true
        var engine = FocusEngine(settings: settings, now: origin)
        var now = origin
        engine.start(now: now)
        now = now.addingTimeInterval(TimeInterval(engine.remaining(at: now)))
        let focusEnded = engine.tick(now: now)
        XCTAssertEqual(focusEnded.count, 1)
        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertEqual(engine.runState, .running)

        now = now.addingTimeInterval(TimeInterval(engine.remaining(at: now)))
        let breakEnded = engine.tick(now: now)
        XCTAssertEqual(breakEnded.count, 1)
        XCTAssertEqual(breakEnded[0].finishedPhase, .shortBreak)
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.focusIndex, 2)
        XCTAssertEqual(engine.runState, .running)
    }

    func testA08_pauseIsExcludedFromNetAndIncludedInGross() {
        var settings = FocusSettings.standard
        settings.focusMinutes = 1
        var engine = FocusEngine(settings: settings, now: origin)
        var now = origin
        engine.start(now: now)
        now = now.addingTimeInterval(20)
        engine.pause(now: now)
        XCTAssertEqual(engine.remaining(at: now), 40)
        now = now.addingTimeInterval(15)
        engine.start(now: now)
        XCTAssertEqual(engine.remaining(at: now), 40)
        now = now.addingTimeInterval(40)
        let events = engine.tick(now: now)
        XCTAssertEqual(events.count, 1)
        let session = events[0].session
        XCTAssertEqual(session.durationNetSeconds, 60)
        XCTAssertEqual(session.durationGrossSeconds, 75)
        XCTAssertEqual(session.startedAt, origin)
        XCTAssertEqual(session.completedAt, origin.addingTimeInterval(75))
        let wall = Int(session.completedAt!.timeIntervalSince(session.startedAt).rounded())
        XCTAssertEqual(session.durationGrossSeconds, wall)
    }

    func testA09_containsMatchIsCaseInsensitive() {
        XCTAssertTrue(ruleMatches("x.com", url: "https://x.com/"))
        XCTAssertTrue(ruleMatches("x.com", url: "https://www.x.com/home"))
        XCTAssertTrue(ruleMatches("x.com", url: "HTTPS://X.COM/Home"))
        XCTAssertFalse(ruleMatches("x.com", url: "https://example.org/"))
    }

    func testA10_starRuleMatchesTheExactURLOnly() {
        let rule = "*https://www.facebook.com"
        XCTAssertTrue(ruleMatches(rule, url: "https://www.facebook.com"))
        XCTAssertTrue(ruleMatches(rule, url: "https://www.facebook.com/"))
        XCTAssertTrue(ruleMatches(rule, url: "HTTPS://www.facebook.com"))
        XCTAssertFalse(ruleMatches(rule, url: "https://business.facebook.com"))
        XCTAssertFalse(ruleMatches(rule, url: "https://www.facebook.com/home"))
        XCTAssertFalse(ruleMatches(rule, url: "https://facebook.com"))
    }

    func testA11_blockModeReplacesOnlyMatchingHTTP() {
        let rules = ["x.com"]
        XCTAssertEqual(verdict("https://x.com/", rules: rules, mode: .block), .replace)
        XCTAssertEqual(verdict("http://x.com/a", rules: rules, mode: .block), .replace)
        XCTAssertEqual(verdict("https://example.org/", rules: rules, mode: .block), .leave)
        XCTAssertEqual(verdict("chrome://settings", rules: rules, mode: .block), .leave)
        XCTAssertEqual(verdict("about:blank", rules: rules, mode: .block), .leave)
        XCTAssertEqual(verdict("ftp://x.com/file", rules: rules, mode: .block), .leave)
    }

    func testA12_allowModeReplacesUnlistedHTTP() {
        let rules = ["x.com"]
        XCTAssertEqual(verdict("https://example.org/", rules: rules, mode: .allow), .replace)
        XCTAssertEqual(verdict("https://x.com/", rules: rules, mode: .allow), .leave)
        XCTAssertEqual(verdict("https://www.x.com/home", rules: rules, mode: .allow), .leave)
        XCTAssertEqual(verdict("chrome://newtab", rules: rules, mode: .allow), .leave)
        XCTAssertEqual(verdict("about:blank", rules: rules, mode: .allow), .leave)
    }

    func testA13_shieldingStaysOffOutsideARunningFocus() {
        let cases: [(SessionPhase, RunState)] = [
            (.focus, .paused),
            (.focus, .idle),
            (.shortBreak, .running),
            (.longBreak, .idle)
        ]
        for (phase, state) in cases {
            let result = shieldVerdict(ShieldInput(
                urlString: "https://x.com/",
                rules: ["x.com"],
                mode: .block,
                phase: phase,
                runState: state
            ))
            XCTAssertEqual(result, .shieldingOff, "\(phase) \(state)")
        }
    }

    func testA14_blockPageIsNeverReplaced() {
        let urls = [
            "file:///tmp/YinerBlock.html",
            "file:///Applications/YinerFocus.app/Contents/Resources/YinerBlock.html?mode=block",
            "file:///Applications/YinerFocus.app/Contents/Resources/YinerBlock.html?mode=allow"
        ]
        for url in urls {
            for mode in [WebListMode.block, WebListMode.allow] {
                let result = verdict(url, rules: ["x.com"], mode: mode)
                XCTAssertNotEqual(result, .replace, url)
                XCTAssertEqual(result, .leave, url)
            }
            let paused = shieldVerdict(ShieldInput(
                urlString: url,
                rules: [],
                mode: .allow,
                phase: .focus,
                runState: .paused
            ))
            XCTAssertNotEqual(paused, .replace)
        }
    }

    func testA15_sampleImportYieldsTheThreeIDs() throws {
        var store = StoreSnapshot.fresh(now: origin)
        let outcome = store.importFlowCSV(try sampleText(), timeZone: shanghai)
        XCTAssertEqual(outcome.added, 3)
        XCTAssertEqual(outcome.failed, 0)
        XCTAssertEqual(store.sessions.map(\.id), [
            "FC38D251-B896-4406-B06F-1C16F5A8649C",
            "23B4F7C2-CE2C-4A0D-9D83-6709F7B81E53",
            "DFE7E03C-3B98-461D-BBAC-95695E0CF79D"
        ])
    }

    func testA16_sampleFieldsArePreserved() throws {
        var store = StoreSnapshot.fresh(now: origin)
        _ = store.importFlowCSV(try sampleText(), timeZone: shanghai)
        let first = try XCTUnwrap(store.sessions.first)
        XCTAssertEqual(first.durationNetSeconds, 5 * 60 + 49)
        XCTAssertEqual(first.durationGrossSeconds, 5 * 60 + 50)
        XCTAssertEqual(first.tag, "学习")
        XCTAssertEqual(first.title, "")
        XCTAssertEqual(first.kind, .focus)
        XCTAssertEqual(WallTime.format(date: first.startedAt, timeZone: shanghai), "2026-11-25 23:46:24")
        XCTAssertEqual(WallTime.format(date: try XCTUnwrap(first.completedAt), timeZone: shanghai), "2026-11-25 23:52:14")
        XCTAssertEqual(store.sessions[2].tag, "")
        XCTAssertNotEqual(first.durationNetSeconds, first.durationGrossSeconds)
    }

    func testA17_importingTwiceDoesNotDuplicate() throws {
        var store = StoreSnapshot.fresh(now: origin)
        let text = try sampleText()
        _ = store.importFlowCSV(text, timeZone: shanghai)
        let second = store.importFlowCSV(text, timeZone: shanghai)
        XCTAssertEqual(store.sessions.count, 3)
        XCTAssertEqual(second.added, 0)
        XCTAssertEqual(second.skipped, 3)
        XCTAssertEqual(Set(store.sessions.map(\.id)).count, 3)
    }

    func testA18_exportMatchesTheSampleShape() throws {
        var store = StoreSnapshot.fresh(now: origin)
        let text = try sampleText()
        _ = store.importFlowCSV(text, timeZone: shanghai)
        let exported = store.exportFlowCSV(timeZone: shanghai)
        let header = exported.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init)
        XCTAssertEqual(header, YinerDefaults.csvHeader)
        XCTAssertFalse(exported.hasSuffix("\n\n"))
        XCTAssertTrue(exported.contains("\"Flow\""))
        XCTAssertTrue(exported.contains("\"\""))
        XCTAssertTrue(exported.contains("\"学习\""))
        XCTAssertTrue(exported.contains("00:05:49"))
        XCTAssertTrue(exported.contains("00:05:50"))
        XCTAssertTrue(exported.contains("2026-11-25 23:46:24"))
        XCTAssertTrue(exported.contains("\"FC38D251-B896-4406-B06F-1C16F5A8649C\""))
        XCTAssertEqual(exported, text)
    }

    func testA19_exportRoundTripsIntoAnEmptyStore() throws {
        var store = StoreSnapshot.fresh(now: origin)
        _ = store.importFlowCSV(try sampleText(), timeZone: shanghai)
        let exported = store.exportFlowCSV(timeZone: shanghai)
        var empty = StoreSnapshot.fresh(now: origin)
        let outcome = empty.importFlowCSV(exported, timeZone: shanghai)
        XCTAssertEqual(outcome.added, 3)
        XCTAssertEqual(outcome.failed, 0)
        XCTAssertEqual(empty.sessions.count, store.sessions.count)
        for (imported, original) in zip(empty.sessions, store.sessions) {
            XCTAssertEqual(imported.id, original.id)
            XCTAssertEqual(imported.title, original.title)
            XCTAssertEqual(imported.tag, original.tag)
            XCTAssertEqual(imported.durationNetSeconds, original.durationNetSeconds)
            XCTAssertEqual(imported.durationGrossSeconds, original.durationGrossSeconds)
            XCTAssertEqual(imported.startedAt, original.startedAt)
            XCTAssertEqual(imported.completedAt, original.completedAt)
            XCTAssertEqual(imported.kind, .focus)
            XCTAssertEqual(imported.typeRaw, "Flow")
        }
    }

    func testA20_calendarTitleUsesTagWhenTheSessionHasNoTitle() {
        let tagged = sampleSession(title: "", tag: "学习")
        let plain = sampleSession(title: "", tag: "")
        let named = sampleSession(title: "读规格", tag: "学习")
        XCTAssertEqual(CalendarText.draft(for: tagged)?.title, "专注 · 学习")
        XCTAssertEqual(CalendarText.draft(for: plain)?.title, "专注")
        XCTAssertEqual(CalendarText.draft(for: named)?.title, "读规格")
        let notes = CalendarText.draft(for: tagged)?.notes ?? ""
        XCTAssertTrue(notes.contains("净时长 00:05:49"))
        XCTAssertTrue(notes.contains("含中断 00:05:50"))
        XCTAssertEqual(notes.split(separator: "\n").count, 2)
        XCTAssertNil(CalendarText.draft(for: FocusSession(
            id: "break",
            kind: .shortBreak,
            typeRaw: "ShortBreak",
            title: "",
            tag: "",
            durationNetSeconds: 60,
            durationGrossSeconds: 60,
            startedAt: origin,
            completedAt: origin.addingTimeInterval(60),
            status: .completed,
            cycleLengthSnapshot: 4
        )))
    }

    private var shanghai: TimeZone {
        TimeZone(identifier: "Asia/Shanghai")!
    }

    private func sampleText() throws -> String {
        let url = flowSampleURL()
        let data = try Data(contentsOf: url)
        return String(decoding: data, as: UTF8.self)
    }

    private func flowSampleURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/samples/flow-export-sample.csv")
    }

    private func verdict(_ url: String, rules: [String], mode: WebListMode) -> ShieldVerdict {
        shieldVerdict(ShieldInput(
            urlString: url,
            rules: rules,
            mode: mode,
            phase: .focus,
            runState: .running
        ))
    }

    private func sampleSession(title: String, tag: String) -> FocusSession {
        FocusSession(
            id: "id",
            kind: .focus,
            typeRaw: "Flow",
            title: title,
            tag: tag,
            durationNetSeconds: 5 * 60 + 49,
            durationGrossSeconds: 5 * 60 + 50,
            startedAt: origin,
            completedAt: origin.addingTimeInterval(350),
            status: .completed,
            cycleLengthSnapshot: 4
        )
    }

    @discardableResult
    private func finishCurrent(_ engine: inout FocusEngine, now: inout Date) -> PhaseCompletion {
        if engine.runState != .running {
            engine.start(now: now)
        }
        now = now.addingTimeInterval(TimeInterval(engine.remaining(at: now)))
        let events = engine.tick(now: now)
        XCTAssertEqual(events.count, 1)
        return events[0]
    }
}

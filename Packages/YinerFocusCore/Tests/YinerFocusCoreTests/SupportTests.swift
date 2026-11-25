import XCTest
@testable import YinerFocusCore

final class SupportTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)
    private var shanghai: TimeZone { TimeZone(identifier: "Asia/Shanghai")! }

    func testConfirmedDefaultsStayInOnePlace() {
        let settings = FocusSettings.standard
        XCTAssertEqual(YinerDefaults.appName, "银耳专注")
        XCTAssertEqual(YinerDefaults.bundleIdentifier, "com.yiner.focus")
        XCTAssertFalse(settings.globalHotkeyEnabled)
        XCTAssertFalse(YinerDefaults.exportBreaks)
        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertTrue(settings.hidePopoverWhenRunning)
        XCTAssertFalse(settings.windowAlwaysOnTop)
        XCTAssertFalse(settings.autoStartBreak)
        XCTAssertFalse(settings.autoStartFocus)
        XCTAssertEqual(settings.webMode, .block)
        XCTAssertEqual(settings.enabledBrowsers, KnownBrowser.allCases)
        XCTAssertFalse(settings.calendarSyncEnabled)
        XCTAssertTrue(YinerDefaults.allowsCustomDuration)
        XCTAssertTrue(YinerDefaults.includesTodayWidget)
        XCTAssertEqual(settings.clamped().focusMinutes, 25)

        var wild = settings
        wild.focusMinutes = 0
        wild.shortBreakMinutes = 200
        wild.cycleLength = 40
        wild.globalHotkeyEnabled = true
        let clamped = wild.clamped()
        XCTAssertEqual(clamped.focusMinutes, 1)
        XCTAssertEqual(clamped.shortBreakMinutes, 90)
        XCTAssertEqual(clamped.cycleLength, 10)
        XCTAssertFalse(clamped.globalHotkeyEnabled)
    }

    func testCustomMinutesApplyWhileIdle() {
        var engine = FocusEngine(settings: .standard, now: origin)
        var settings = engine.settings
        settings.focusMinutes = 12
        engine.updateSettings(settings, now: origin)
        XCTAssertEqual(engine.remaining(at: origin), 12 * 60)
    }

    func testSkipStartsFocusOnlyWhenThatSwitchIsOn() {
        var settings = FocusSettings.standard
        settings.autoStartFocus = true
        var engine = FocusEngine(settings: settings, now: origin)
        var now = origin
        engine.start(now: now)
        now = now.addingTimeInterval(TimeInterval(engine.remaining(at: now)))
        _ = engine.tick(now: now)
        XCTAssertEqual(engine.phase, .shortBreak)
        engine.skipBreak(now: now)
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.focusIndex, 2)
        XCTAssertEqual(engine.runState, .running)
    }

    func testResetKeepsAnIncompleteFocus() {
        var settings = FocusSettings.standard
        settings.focusMinutes = 1
        var engine = FocusEngine(settings: settings, now: origin)
        engine.title = "半截"
        engine.tag = "学习"
        engine.start(now: origin)
        let later = origin.addingTimeInterval(10)
        let partial = engine.resetCycle(now: later)
        XCTAssertEqual(partial?.status, .incomplete)
        XCTAssertEqual(partial?.title, "半截")
        XCTAssertEqual(partial?.tag, "学习")
        XCTAssertEqual(partial?.durationNetSeconds, 10)
        XCTAssertEqual(partial?.kind, .focus)
        XCTAssertEqual(engine.title, "")
        XCTAssertEqual(engine.tag, "学习")
    }

    func testContainsMatchIsLiteralAndExactSlashRuleIsOneSlash() {
        XCTAssertTrue(ruleMatches("x.com", url: "https://x.com.evil.example/"))
        XCTAssertFalse(ruleMatches("*https://www.facebook.com//", url: "https://www.facebook.com"))
        XCTAssertTrue(ruleMatches("*https://www.facebook.com/", url: "https://www.facebook.com"))
    }

    func testAllowModeDoesNotTreatARemoteCopyOfTheFileNameAsTheBlockPage() {
        let result = shieldVerdict(ShieldInput(
            urlString: "https://evil.example/YinerBlock.html",
            rules: ["x.com"],
            mode: .allow,
            phase: .focus,
            runState: .running
        ))
        XCTAssertEqual(result, .replace)
    }

    func testAppHidingOnlyWhileFocusIsRunningAndNeverHidesItself() {
        let blocked: Set<String> = ["com.example.chat"]
        XCTAssertTrue(shouldHideApplication(
            bundleID: "com.example.chat",
            ownBundleID: YinerDefaults.bundleIdentifier,
            blockedBundleIDs: blocked,
            phase: .focus,
            runState: .running
        ))
        XCTAssertFalse(shouldHideApplication(
            bundleID: YinerDefaults.bundleIdentifier,
            ownBundleID: YinerDefaults.bundleIdentifier,
            blockedBundleIDs: blocked.union([YinerDefaults.bundleIdentifier]),
            phase: .focus,
            runState: .running
        ))
        XCTAssertFalse(shouldHideApplication(
            bundleID: "com.example.chat",
            ownBundleID: YinerDefaults.bundleIdentifier,
            blockedBundleIDs: blocked,
            phase: .focus,
            runState: .paused
        ))
        XCTAssertFalse(shouldHideApplication(
            bundleID: "com.example.chat",
            ownBundleID: YinerDefaults.bundleIdentifier,
            blockedBundleIDs: blocked,
            phase: .shortBreak,
            runState: .running
        ))
    }

    func testBrowserSummaryUsesTheListedOrder() {
        XCTAssertEqual(browserSelectionSummary(selected: KnownBrowser.allCases), "Safari + 2")
        XCTAssertEqual(browserSelectionSummary(selected: [.arc]), "Arc")
        XCTAssertEqual(browserSelectionSummary(selected: [.arc, .chrome]), "Google Chrome + 1")
        XCTAssertEqual(browserSelectionSummary(selected: []), "未选择")
        XCTAssertFalse(KnownBrowser.allCases.contains(where: { $0.displayName == "Cra" }))
    }

    func testMenuBarLabelDistinguishesPhaseAndPause() {
        var engine = FocusEngine(settings: .standard, now: origin)
        XCTAssertEqual(engine.menuBarLabel(at: origin).text, "○ 专注")
        engine.start(now: origin)
        XCTAssertEqual(engine.menuBarLabel(at: origin).text, "● 25:00")
        XCTAssertEqual(engine.menuBarLabel(at: origin).style, .focusRunning)
        engine.pause(now: origin.addingTimeInterval(1))
        XCTAssertTrue(engine.menuBarLabel(at: origin.addingTimeInterval(30)).text.hasPrefix("暂停 "))
        engine.runState = .idle
        engine.phase = .shortBreak
        engine.remainingSeconds = 5 * 60
        XCTAssertEqual(engine.menuBarLabel(at: origin).style, .breakIdle)
        engine.runState = .running
        engine.runningSince = origin
        engine.remainingSeconds = 5 * 60
        XCTAssertEqual(engine.menuBarLabel(at: origin).text, "● 5:00")
        XCTAssertEqual(engine.menuBarLabel(at: origin).style, .breakRunning)
    }

    func testStatisticsMatchTheFilteredFocusList() throws {
        var store = StoreSnapshot.fresh(now: origin)
        _ = store.importFlowCSV(try sampleText(), timeZone: shanghai)
        let anchor = WallTime.parse("2026-11-25 12:00:00", timeZone: shanghai)!
        let sessions = focusSessionsForStats(stored: store.sessions, active: nil, query: SessionQuery(), range: nil)
        let day = aggregate(sessions: sessions, scope: .day, anchor: anchor, timeZone: shanghai)
        XCTAssertEqual(day.buckets.count, 24)
        XCTAssertEqual(day.buckets[23].count, 3)
        XCTAssertEqual(day.buckets[23].durationNetSeconds, 685)
        XCTAssertEqual(day.totalCount, 3)

        let week = aggregate(sessions: sessions, scope: .week, anchor: anchor, timeZone: shanghai)
        XCTAssertEqual(week.buckets.map(\.label), ["周一", "周二", "周三", "周四", "周五", "周六", "周日"])
        XCTAssertEqual(week.buckets[2].count, 3)
        XCTAssertEqual(WallTime.format(date: week.buckets[0].start, timeZone: shanghai), "2026-11-23 00:00:00")

        let month = aggregate(sessions: sessions, scope: .month, anchor: anchor, timeZone: shanghai)
        XCTAssertEqual(month.buckets.first { $0.label == "25" }?.count, 3)
        let year = aggregate(sessions: sessions, scope: .year, anchor: anchor, timeZone: shanghai)
        XCTAssertEqual(year.buckets.first { $0.label == "11月" }?.count, 3)

        let study = focusSessionsForStats(
            stored: store.sessions,
            active: nil,
            query: SessionQuery(tag: "学习"),
            range: nil
        )
        let studyDay = aggregate(sessions: study, scope: .day, anchor: anchor, timeZone: shanghai)
        XCTAssertEqual(studyDay.totalCount, 2)
        XCTAssertEqual(studyDay.totalDurationSeconds, 444)

        let range = periodRange(scope: .day, anchor: anchor, timeZone: shanghai)
        let listed = focusSessionsForStats(stored: store.sessions, active: nil, query: SessionQuery(), range: range)
        XCTAssertEqual(listed.count, day.totalCount)
        XCTAssertEqual(listed.reduce(0) { $0 + $1.durationNetSeconds }, day.totalDurationSeconds)

        let today = todaySummary(sessions: store.sessions, now: anchor, timeZone: shanghai)
        XCTAssertEqual(today.day, "2026-11-25")
        XCTAssertEqual(today.focusCount, 3)
        XCTAssertEqual(today.focusDurationSeconds, 685)
        XCTAssertFalse(isCurrentPeriod(scope: .day, anchor: anchor.addingTimeInterval(-86_400), now: anchor, timeZone: shanghai))
        XCTAssertTrue(isCurrentPeriod(scope: .day, anchor: anchor, now: anchor, timeZone: shanghai))
    }

    func testIncompleteSessionsStayOutUntilAsked() {
        let done = FocusSession(
            id: "done", kind: .focus, typeRaw: "Flow", title: "", tag: "学习",
            durationNetSeconds: 60, durationGrossSeconds: 60,
            startedAt: origin, completedAt: origin.addingTimeInterval(60),
            status: .completed, cycleLengthSnapshot: 4
        )
        let partial = FocusSession(
            id: "partial", kind: .focus, typeRaw: "Flow", title: "", tag: "",
            durationNetSeconds: 10, durationGrossSeconds: 10,
            startedAt: origin, completedAt: nil,
            status: .incomplete, cycleLengthSnapshot: 4
        )
        let hidden = focusSessionsForStats(
            stored: [done, partial], active: nil, query: SessionQuery(), range: nil
        )
        XCTAssertEqual(hidden.map(\.id), ["done"])
        let shown = focusSessionsForStats(
            stored: [done, partial], active: nil,
            query: SessionQuery(includeIncomplete: true), range: nil
        )
        XCTAssertEqual(Set(shown.map(\.id)), Set(["done", "partial"]))
    }

    func testImportReportsABadRowAndKeepsTheGoodOnes() throws {
        var store = StoreSnapshot.fresh(now: origin)
        let text = try sampleText() + "\n\"Flow\",\"\",\"阅读\",00:00:02,00:00:02,2026-11-25 22:00:00,2026-11-25 22:00:02,\"NEW-1\"\n\"Flow\",\"坏行\",\"\",nope,00:00:01,2026-11-25 23:00:00,2026-11-25 23:00:01,\"BAD\""
        let outcome = store.importFlowCSV(text, timeZone: shanghai)
        XCTAssertEqual(outcome.added, 4)
        XCTAssertEqual(outcome.failed, 1)
        XCTAssertEqual(outcome.errors.first?.line, 6)
        XCTAssertEqual(store.sessions.count, 4)
        XCTAssertEqual(outcome.createdTags, ["阅读"])
        XCTAssertEqual(store.tags.filter { $0.name == "学习" }.count, 1)
        XCTAssertEqual(store.tags.filter { $0.name == "阅读" }.count, 1)
    }

    func testUnknownTypeRoundTripsAndBreaksStayOutOfTheExport() {
        var store = StoreSnapshot.fresh(now: origin)
        let raw = """
        \(YinerDefaults.csvHeader)
        "Mystery","保持","",00:00:02,00:00:03,2026-11-25 10:00:00,2026-11-25 10:00:03,"KEEP-1"
        """
        let outcome = store.importFlowCSV(raw, timeZone: shanghai)
        XCTAssertEqual(outcome.added, 1)
        XCTAssertEqual(store.sessions[0].kind, .preserved)
        XCTAssertEqual(store.sessions[0].typeRaw, "Mystery")
        store.sessions.append(FocusSession(
            id: "break-1", kind: .shortBreak, typeRaw: "ShortBreak", title: "", tag: "",
            durationNetSeconds: 30, durationGrossSeconds: 30,
            startedAt: origin, completedAt: origin.addingTimeInterval(30),
            status: .completed, cycleLengthSnapshot: 4
        ))
        let exported = store.exportFlowCSV(timeZone: shanghai)
        XCTAssertTrue(exported.contains("\"Mystery\""))
        XCTAssertTrue(exported.contains("\"保持\""))
        XCTAssertFalse(exported.contains("ShortBreak"))
        var again = StoreSnapshot.fresh(now: origin)
        _ = again.importFlowCSV(exported, timeZone: shanghai)
        XCTAssertEqual(again.sessions.map(\.typeRaw), ["Mystery"])
        XCTAssertEqual(again.sessions[0].title, "保持")
    }

    func testQuotedTitleSurvivesACommaAndAQuote() {
        var store = StoreSnapshot.fresh(now: origin)
        let text = """
        \(YinerDefaults.csvHeader)
        "Flow","他说""好"", 继续","学习",00:00:05,00:00:05,2026-11-25 08:00:00,2026-11-25 08:00:05,"Q-1"
        """
        let outcome = store.importFlowCSV(text, timeZone: shanghai)
        XCTAssertEqual(outcome.failed, 0)
        XCTAssertEqual(store.sessions[0].title, "他说\"好\", 继续")
        let exported = store.exportFlowCSV(timeZone: shanghai)
        var empty = StoreSnapshot.fresh(now: origin)
        _ = empty.importFlowCSV(exported, timeZone: shanghai)
        XCTAssertEqual(empty.sessions[0].title, "他说\"好\", 继续")
    }

    func testBadHeaderDoesNotImportSilently() {
        var store = StoreSnapshot.fresh(now: origin)
        let outcome = store.importFlowCSV("A,B\n1,2\n", timeZone: shanghai)
        XCTAssertEqual(outcome.added, 0)
        XCTAssertEqual(outcome.failed, 1)
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertFalse(outcome.summary.isEmpty)
    }

    func testDuplicateIDInsideOneFileIsSkipped() {
        var store = StoreSnapshot.fresh(now: origin)
        let row = "\"Flow\",\"\",\"\",00:00:01,00:00:01,2026-11-25 08:00:00,2026-11-25 08:00:01,\"SAME\""
        let text = "\(YinerDefaults.csvHeader)\n\(row)\n\(row)"
        let outcome = store.importFlowCSV(text, timeZone: shanghai)
        XCTAssertEqual(outcome.added, 1)
        XCTAssertEqual(outcome.skipped, 1)
        XCTAssertEqual(store.sessions.count, 1)
    }

    func testManualEntryAndTagRename() throws {
        let start = WallTime.parse("2026-11-25 09:00:00", timeZone: shanghai)!
        let end = WallTime.parse("2026-11-25 09:25:00", timeZone: shanghai)!
        let session = try XCTUnwrap(ManualEntry.completedFocus(
            title: " 补上 ", tag: "学习", startedAt: start, completedAt: end, cycleLength: 4
        ))
        XCTAssertEqual(session.title, "补上")
        XCTAssertEqual(session.durationNetSeconds, 25 * 60)
        XCTAssertEqual(session.durationGrossSeconds, 25 * 60)
        XCTAssertNil(ManualEntry.completedFocus(
            title: "", tag: "", startedAt: end, completedAt: start, cycleLength: 4
        ))

        var tags = TagLibrary.defaults
        var sessions = [session]
        try TagLibrary.rename(id: tags[2].id, to: "自习", tags: &tags, sessions: &sessions)
        XCTAssertEqual(sessions[0].tag, "自习")
        XCTAssertThrowsError(try TagLibrary.rename(id: tags[2].id, to: "工作", tags: &tags, sessions: &sessions))
    }

    func testWebRuleRejectsDuplicatesAndCalendarNotesKeepTheTagOnTheSecondLine() {
        var rules: [WebRule] = []
        XCTAssertNotNil(WebRuleEdit.add(" x.com ", to: &rules))
        XCTAssertNil(WebRuleEdit.add("X.COM", to: &rules))
        XCTAssertNil(WebRuleEdit.add("   ", to: &rules))
        XCTAssertEqual(rules.count, 1)

        let named = FocusSession(
            id: "n", kind: .focus, typeRaw: "Flow", title: "写代码", tag: "学习",
            durationNetSeconds: 10, durationGrossSeconds: 12,
            startedAt: origin, completedAt: origin.addingTimeInterval(12),
            status: .completed, cycleLengthSnapshot: 4
        )
        let draft = CalendarText.draft(for: named)
        XCTAssertEqual(draft?.title, "写代码")
        XCTAssertEqual(draft?.notes, "净时长 00:00:10\n含中断 00:00:12（学习）")
        XCTAssertEqual(draft?.start, named.startedAt)
        XCTAssertEqual(draft?.end, named.completedAt)
    }

    func testStoreRoundTripDoesNotOverwriteACorruptFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yiner-store-\(UUID().uuidString)", isDirectory: true)
        let url = LocalStore.storeURL(in: directory)
        var snapshot = StoreSnapshot.fresh(now: origin)
        snapshot.settings.focusMinutes = 50
        snapshot.webRules = [WebRule(id: "w1", pattern: "x.com")]
        snapshot.appRules = [AppRule(bundleID: "com.example.chat", displayName: "聊天")]
        snapshot.engine.title = "在写"
        try LocalStore.save(snapshot, to: url)
        guard case .loaded(let loaded) = LocalStore.load(from: url) else {
            return XCTFail("应该读回存档")
        }
        XCTAssertEqual(loaded.settings.focusMinutes, 50)
        XCTAssertEqual(loaded.webRules.map(\.pattern), ["x.com"])
        XCTAssertEqual(loaded.appRules.first?.displayName, "聊天")
        XCTAssertEqual(loaded.engine.title, "在写")

        try Data("not json".utf8).write(to: url)
        guard case .failed = LocalStore.load(from: url) else {
            return XCTFail("坏文件应该报告失败，而不是当成空存档")
        }
        let payload = todaySummary(sessions: [], now: origin, timeZone: shanghai)
        let widgetURL = directory.appendingPathComponent(YinerDefaults.widgetFileName)
        try WidgetSummaryFile.save(payload, to: widgetURL)
        XCTAssertEqual(WidgetSummaryFile.load(from: widgetURL)?.focusCount, 0)
        try? FileManager.default.removeItem(at: directory)
    }

    func testBlockPageCopyIsOriginal() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App/YinerFocus/Resources/YinerBlock.html")
        let html = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        XCTAssertFalse(html.localizedCaseInsensitiveContains("flow"))
        XCTAssertFalse(html.contains("封锁"))
        XCTAssertTrue(html.contains("已暂停访问"))
        XCTAssertTrue(html.contains("不在你的允许名单中"))
        XCTAssertTrue(html.contains("在你的拦截名单中"))
    }

    func testClockAndHMSFormatting() {
        XCTAssertEqual(formatClock(0), "0:00")
        XCTAssertEqual(formatClock(25 * 60), "25:00")
        XCTAssertEqual(formatClock(90 * 60), "1:30:00")
        XCTAssertEqual(formatHMS(5 * 60 + 49), "00:05:49")
        XCTAssertEqual(parseHMS("100:00:01"), 100 * 3600 + 1)
        XCTAssertNil(parseHMS("1:60:00"))
    }

    private func sampleText() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/samples/flow-export-sample.csv")
        return String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }
}

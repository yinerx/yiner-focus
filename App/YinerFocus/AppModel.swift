import AppKit
import SwiftUI
import UniformTypeIdentifiers
import YinerFocusCore

final class AppModel: ObservableObject {
    @Published private(set) var snapshot: StoreSnapshot
    @Published private(set) var now = Date()
    @Published var notificationDenied = false
    @Published var calendarDenied = false
    @Published var calendars: [CalendarChoice] = []
    @Published var loginItemMessage: String?
    @Published var importSummary: String?
    @Published var loadError: String?
    @Published var browserMessages: [String: String] = [:]
    @Published var widgetGroupAvailable = false
    @Published var hideBurstMessage: String?
    @Published var tagError: String?
    @Published var calendarWriteError: String?

    var onChromeChange: () -> Void = {}
    var onHidePopover: () -> Void = {}
    var onShowSettings: () -> Void = {}
    var onShowStats: () -> Void = {}

    let calendarSync = CalendarSync()
    private var storeURL: URL?
    private var canPersist = false
    private var lastWidgetDay: String?

    init() {
        snapshot = .fresh()
    }

    var settings: FocusSettings {
        get { snapshot.settings }
        set {
            var snap = snapshot
            snap.settings = newValue.clamped()
            var engine = snap.engine
            engine.updateSettings(snap.settings, now: Date())
            snap.engine = engine
            snapshot = snap
            save()
            applySideEffects()
        }
    }

    func binding<T>(_ keyPath: WritableKeyPath<FocusSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in
                var updated = self.settings
                updated[keyPath: keyPath] = newValue
                self.settings = updated
            }
        )
    }

    func boot() {
        loadStore()
        AppearanceBridge.apply(settings.appearance)
        syncLoginItem()
        let moment = Date()
        var snap = snapshot
        if snap.settings.resetCycleAtLaunch, let partial = snap.engine.resetCycle(now: moment) {
            snap.sessions.append(partial)
        }
        if snap.settings.startFocusAtLaunch, snap.engine.runState == .idle, snap.engine.phase == .focus {
            snap.engine.start(now: moment)
        }
        let events = snap.engine.tick(now: moment)
        for event in events {
            snap.sessions.append(event.session)
        }
        snapshot = snap
        now = moment
        save()
        writeWidget()
        events.forEach(handleCompletion)
        refreshNotificationStatus()
        widgetGroupAvailable = WidgetBridge.containerAvailable
        if settings.calendarSyncEnabled {
            requestCalendarAccess()
        }
    }

    func tick() {
        now = Date()
        var snap = snapshot
        let events = snap.engine.tick(now: now)
        guard !events.isEmpty else {
            refreshWidgetIfDayChanged()
            return
        }
        for event in events {
            snap.sessions.append(event.session)
        }
        snapshot = snap
        save()
        writeWidget()
        events.forEach(handleCompletion)
        onChromeChange()
    }

    func toggleTimer() {
        let wasRunning = snapshot.engine.runState == .running
        updateEngine { $0.toggle(now: Date()) }
        if !wasRunning,
           snapshot.engine.runState == .running,
           settings.hidePopoverWhenRunning {
            onHidePopover()
        }
    }

    func skipBreak() {
        updateEngine { $0.skipBreak(now: Date()) }
    }

    func resetCycle() {
        var partial: FocusSession?
        updateEngine { partial = $0.resetCycle(now: Date()) }
        guard let partial else { return }
        var snap = snapshot
        snap.sessions.append(partial)
        snapshot = snap
        save()
        writeWidget()
    }

    func setTitle(_ title: String) {
        guard snapshot.engine.title != title else { return }
        updateEngine { $0.title = title }
    }

    func setTag(_ tag: String?) {
        guard snapshot.engine.tag != tag else { return }
        updateEngine { $0.tag = tag }
    }

    func showSettings() { onShowSettings() }
    func showStats() { onShowStats() }

    func setNotifyFocus(_ enabled: Bool) {
        var updated = settings
        updated.notifyFocusEnd = enabled
        settings = updated
        if enabled { requestNotifications() }
    }

    func setNotifyBreak(_ enabled: Bool) {
        var updated = settings
        updated.notifyBreakEnd = enabled
        settings = updated
        if enabled { requestNotifications() }
    }

    func setCalendarSync(_ enabled: Bool) {
        var updated = settings
        updated.calendarSyncEnabled = enabled
        settings = updated
        calendarWriteError = nil
        guard enabled else { return }
        requestCalendarAccess()
    }

    func setCalendarIdentifier(_ identifier: String?) {
        var updated = settings
        updated.calendarIdentifier = identifier
        settings = updated
        calendarWriteError = nil
    }

    func setBrowser(_ browser: KnownBrowser, enabled: Bool) {
        var updated = settings
        if enabled {
            if !updated.enabledBrowsers.contains(browser) {
                updated.enabledBrowsers.append(browser)
            }
        } else {
            updated.enabledBrowsers.removeAll { $0 == browser }
        }
        settings = updated
    }

    func addWebRule(_ text: String) -> Bool {
        var snap = snapshot
        let created = WebRuleEdit.add(text, to: &snap.webRules) != nil
        guard created else { return false }
        snapshot = snap
        save()
        return true
    }

    func removeWebRules(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        var snap = snapshot
        snap.webRules.removeAll { ids.contains($0.id) }
        snapshot = snap
        save()
    }

    func removeApps(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        var snap = snapshot
        snap.appRules.removeAll { ids.contains($0.bundleID) }
        snapshot = snap
        save()
    }

    func pickApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "加入名单"
        guard panel.runModal() == .OK else { return }
        var snap = snapshot
        var missing: [String] = []
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else {
                missing.append(url.deletingPathExtension().lastPathComponent)
                continue
            }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            AppRuleEdit.add(bundleID: identifier, displayName: name, to: &snap.appRules)
        }
        snapshot = snap
        save()
        if !missing.isEmpty {
            importSummary = "这些项目没有 Bundle ID，没有加入：\(missing.joined(separator: "、"))"
        }
    }

    func addTag(name: String, colorHex: String) {
        var snap = snapshot
        do {
            try TagLibrary.add(name: name, colorHex: colorHex, tags: &snap.tags)
            snapshot = snap
            tagError = nil
            save()
        } catch {
            tagError = tagMessage(error)
        }
    }

    func renameTag(id: String, to name: String) {
        var snap = snapshot
        let oldName = snap.tags.first { $0.id == id }?.name
        do {
            try TagLibrary.rename(id: id, to: name, tags: &snap.tags, sessions: &snap.sessions)
            if let oldName, snap.engine.tag == oldName {
                snap.engine.tag = snap.tags.first { $0.id == id }?.name
            }
            snapshot = snap
            tagError = nil
            save()
        } catch {
            tagError = tagMessage(error)
        }
    }

    func deleteTag(id: String) {
        var snap = snapshot
        let name = snap.tags.first { $0.id == id }?.name
        TagLibrary.remove(id: id, tags: &snap.tags)
        if let name, snap.engine.tag == name {
            snap.engine.tag = nil
        }
        snapshot = snap
        save()
    }

    func moveTag(id: String, direction: Int) {
        var snap = snapshot
        TagLibrary.move(id: id, direction: direction, tags: &snap.tags)
        snapshot = snap
        save()
    }

    func setTagColor(id: String, hex: String) {
        var snap = snapshot
        TagLibrary.setColor(id: id, colorHex: hex, tags: &snap.tags)
        snapshot = snap
        save()
    }

    func importWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "导入"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importFile(url)
    }

    func exportWithPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "银耳专注-导出.csv"
        panel.prompt = "导出"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = snapshot.exportFlowCSV(timeZone: .current)
        do {
            try Data(text.utf8).write(to: url)
            let rows = max(0, text.split(separator: "\n", omittingEmptySubsequences: false).count - 1)
            importSummary = "已导出 \(rows) 条。"
        } catch {
            importSummary = "导出失败。\(error.localizedDescription)"
        }
    }

    func resetStatistics() {
        var snap = snapshot
        snap.sessions = []
        snapshot = snap
        save()
        writeWidget()
    }

    func deleteSession(id: String) {
        var snap = snapshot
        snap.sessions.removeAll { $0.id == id }
        snapshot = snap
        save()
        writeWidget()
    }

    func addManual(title: String, tag: String, startedAt: Date, completedAt: Date) -> String? {
        guard let session = ManualEntry.completedFocus(
            title: title,
            tag: tag,
            startedAt: startedAt,
            completedAt: completedAt,
            cycleLength: settings.cycleLength
        ) else {
            return "结束时间要晚于开始时间。"
        }
        var snap = snapshot
        if !session.tag.isEmpty {
            TagLibrary.ensure(name: session.tag, tags: &snap.tags)
        }
        snap.sessions.append(session)
        snapshot = snap
        save()
        writeWidget()
        if let draft = CalendarText.draft(for: session) {
            writeCalendar(draft)
        }
        return nil
    }

    func applyBrowserPoll(_ messages: [KnownBrowser: String?]) {
        var next = browserMessages
        for (browser, message) in messages {
            if let message, !message.isEmpty {
                next[browser.rawValue] = message
            } else {
                next.removeValue(forKey: browser.rawValue)
            }
        }
        browserMessages = next
    }

    func noteHideBurst() {
        hideBurstMessage = "几个被拦截的应用在互相抢到前台，已暂时停下隐藏。点回你正在用的应用后会恢复。"
    }

    func save() {
        guard canPersist, let storeURL else { return }
        do {
            try LocalStore.save(snapshot, to: storeURL)
        } catch {
            loadError = "没能写入存档。\(error.localizedDescription)"
        }
    }

    private func loadStore() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let url = LocalStore.storeURL(in: support)
        storeURL = url
        switch LocalStore.load(from: url) {
        case .fresh:
            snapshot = .fresh(now: Date())
            canPersist = true
        case .loaded(let stored):
            snapshot = stored
            canPersist = true
        case .failed(let message):
            loadError = "本机存档读不出来，原文件没有被覆盖。\(message)"
            snapshot = .fresh(now: Date())
            canPersist = false
        }
    }

    private func updateEngine(_ body: (inout FocusEngine) -> Void) {
        var snap = snapshot
        body(&snap.engine)
        snapshot = snap
        save()
        onChromeChange()
    }

    private func applySideEffects() {
        AppearanceBridge.apply(settings.appearance)
        syncLoginItem()
        onChromeChange()
    }

    private func syncLoginItem() {
        loginItemMessage = LoginItemBridge.sync(enabled: settings.launchAtLogin)
    }

    private func handleCompletion(_ event: PhaseCompletion) {
        if event.shouldNotify {
            let title: String
            let body: String
            switch event.finishedPhase {
            case .focus:
                title = "专注结束"
                body = "这一段已经完成。"
            case .shortBreak, .longBreak:
                title = "休息结束"
                body = "可以开始下一段专注。"
            }
            Notifier.deliver(title: title, body: body) { [weak self] denied in
                if denied { self?.notificationDenied = true }
            }
        }
        if let draft = CalendarText.draft(for: event.session) {
            writeCalendar(draft)
        }
    }

    private func writeCalendar(_ draft: CalendarEventDraft) {
        guard settings.calendarSyncEnabled else { return }
        guard let calendarID = settings.calendarIdentifier else {
            calendarWriteError = "还没有选择日历，这场专注没有写入。"
            return
        }
        do {
            try calendarSync.write(draft, calendarID: calendarID)
            calendarWriteError = nil
        } catch {
            calendarWriteError = error.localizedDescription
        }
    }

    private func requestCalendarAccess() {
        calendarSync.requestAccess { [weak self] granted in
            guard let self else { return }
            self.calendarDenied = !granted
            if granted {
                self.calendars = self.calendarSync.calendars()
            }
        }
    }

    private func requestNotifications() {
        Notifier.requestAccess { [weak self] granted in
            self?.notificationDenied = !granted
        }
    }

    private func refreshNotificationStatus() {
        Notifier.refreshDenied { [weak self] denied in
            self?.notificationDenied = denied
        }
    }

    private func writeWidget() {
        let payload = todaySummary(sessions: snapshot.sessions, now: now, timeZone: .current)
        lastWidgetDay = payload.day
        WidgetBridge.write(payload)
    }

    private func refreshWidgetIfDayChanged() {
        let day = dayStamp(now, timeZone: .current)
        if day != lastWidgetDay {
            writeWidget()
        }
    }

    private func importFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            importSummary = "无法读取这个文件。请确认它是 UTF-8 文本。"
            return
        }
        var snap = snapshot
        let outcome = snap.importFlowCSV(text, timeZone: .current)
        snapshot = snap
        save()
        writeWidget()
        importSummary = outcome.summary
    }

    private func tagMessage(_ error: Error) -> String {
        guard let tagError = error as? TagEditError else { return "标签没有改成。" }
        switch tagError {
        case .emptyName: return "标签名称不能是空的。"
        case .duplicateName: return "已经有这个标签了。"
        case .missing: return "没有找到这个标签。"
        }
    }
}

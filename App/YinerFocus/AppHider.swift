import AppKit
import YinerFocusCore

/// 专注进行中，把阻止名单里刚被激活的应用退到后台。不结束进程。
final class AppHider {
    private var token: NSObjectProtocol?
    private var hideTimes: [Date] = []
    private var pausedUntil: Date?

    func start(model: AppModel) {
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak model] note in
            guard
                let self,
                let model,
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self.handle(app, model: model)
        }
    }

    private func handle(_ app: NSRunningApplication, model: AppModel) {
        let now = Date()
        if let pausedUntil, now < pausedUntil { return }
        let own = Bundle.main.bundleIdentifier ?? YinerDefaults.bundleIdentifier
        let blocked = Set(model.snapshot.appRules.map(\.bundleID))
        let engine = model.snapshot.engine
        guard shouldHideApplication(
            bundleID: app.bundleIdentifier,
            ownBundleID: own,
            blockedBundleIDs: blocked,
            phase: engine.phase,
            runState: engine.runState
        ) else { return }

        hideTimes = hideTimes.filter { now.timeIntervalSince($0) < YinerDefaults.appHideBurstWindowSeconds }
        hideTimes.append(now)
        if hideTimes.count > YinerDefaults.appHideBurstLimit {
            pausedUntil = now.addingTimeInterval(2)
            model.noteHideBurst()
            return
        }
        app.hide()
    }
}

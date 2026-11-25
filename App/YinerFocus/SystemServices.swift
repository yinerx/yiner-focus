import EventKit
import Foundation
import ServiceManagement
import UserNotifications
import WidgetKit
import YinerFocusCore

struct CalendarChoice: Identifiable, Equatable {
    var id: String
    var title: String
}

enum CalendarWriteError: LocalizedError {
    case missingCalendar

    var errorDescription: String? {
        "没有找到所选的日历，请在设置里重选一个。"
    }
}

final class CalendarSync {
    private let store = EKEventStore()

    func requestAccess(completion: @escaping (Bool) -> Void) {
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    func calendars() -> [CalendarChoice] {
        store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map { CalendarChoice(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func write(_ draft: CalendarEventDraft, calendarID: String) throws {
        guard let calendar = store.calendar(withIdentifier: calendarID) else {
            throw CalendarWriteError.missingCalendar
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = draft.title
        event.notes = draft.notes
        event.startDate = draft.start
        event.endDate = draft.end
        event.timeZone = TimeZone.current
        try store.save(event, span: .thisEvent, commit: true)
    }
}

enum Notifier {
    static func requestAccess(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    static func refreshDenied(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus == .denied)
            }
        }
    }

    static func deliver(title: String, body: String, denied: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    post(title: title, body: body)
                    denied(false)
                case .denied:
                    denied(true)
                case .notDetermined:
                    requestAccess { granted in
                        if granted {
                            post(title: title, body: body)
                        }
                        denied(!granted)
                    }
                @unknown default:
                    denied(false)
                }
            }
        }
    }

    private static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

enum LoginItemBridge {
    static func sync(enabled: Bool) -> String? {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
                if service.status == .requiresApproval {
                    return "请到系统设置 › 通用 › 登录项，允许银耳专注。"
                }
            } else if service.status == .enabled {
                try service.unregister()
            }
            return nil
        } catch {
            return "登录项没有改成功。\(error.localizedDescription)"
        }
    }
}

enum WidgetBridge {
    static var containerAvailable: Bool {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: YinerDefaults.appGroupIdentifier
        ) != nil
    }

    static func write(_ payload: TodayWidgetPayload) {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: YinerDefaults.appGroupIdentifier
        ) else { return }
        let url = WidgetSummaryFile.fileURL(in: container)
        try? WidgetSummaryFile.save(payload, to: url)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

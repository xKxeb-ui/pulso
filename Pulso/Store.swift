import SwiftUI
import UserNotifications

struct Upcoming: Identifiable, Hashable {
    let id: String
    let date: Date
    let title: String
    let body: String
}

/// App state plus the notification queue.
/// iOS keeps at most 64 pending local notifications per app, so the queue is
/// topped up whenever the app is active or a notification arrives in foreground.
@MainActor
@Observable
final class Store {
    var config: Config
    private(set) var running: Bool
    private(set) var upcoming: [Upcoming] = []
    private(set) var permission: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored private var saved: Config
    @ObservationIgnored private var tail: Task<Void, Never>?
    private let center = UNUserNotificationCenter.current()
    private let relay = NotificationRelay()

    private static let queuePrefix = "pulso.q."
    private static let capacity = 64

    init() {
        let defaults = UserDefaults.standard
        let loaded = defaults.data(forKey: "config")
            .flatMap { try? JSONDecoder().decode(Config.self, from: $0) } ?? Config()
        config = loaded
        saved = loaded
        running = defaults.bool(forKey: "running")
        relay.store = self
        center.delegate = relay
    }

    var renderer: Renderer { Renderer(config: config) }

    // MARK: Public actions

    func wake() async {
        await serial {
            self.permission = await self.center.notificationSettings().authorizationStatus
            await self.fill()
        }
    }

    func refill() async {
        await serial { await self.fill() }
    }

    func start() async {
        await serial {
            guard await self.authorize() else { return }
            await self.clearQueue()
            self.horizon = nil
            self.setRunning(true)
            await self.fill()
        }
    }

    func stop() async {
        await serial {
            self.setRunning(false)
            await self.clearQueue()
            self.horizon = nil
            self.upcoming = []
        }
    }

    /// Persists edits (debounced by the caller) and rebuilds the queue with them.
    func commit() async {
        guard config != saved else { return }
        saved = config
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "config")
        }
        guard running else { return }
        await serial {
            await self.clearQueue()
            self.horizon = nil
            await self.fill()
        }
    }

    func test() async {
        guard await authorize() else { return }
        let rendered = renderer.render(config.activeTemplate, using: &system)
        let request = UNNotificationRequest(
            identifier: "pulso.t.\(UUID().uuidString)",
            content: content(rendered, at: nil),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await center.add(request)
    }

    func clearDelivered() {
        center.removeAllDeliveredNotifications()
    }

    // MARK: Queue

    @ObservationIgnored private var system = SystemRandomNumberGenerator()

    /// Fire date of the last queued notification, so refills keep the rhythm.
    private var horizon: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: "horizon")
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "horizon") }
    }

    private func fill() async {
        guard running else {
            await reload()
            return
        }
        let pending = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(Self.queuePrefix) }
        var count = pending.count
        var last = count == 0 ? Date.now : max(horizon ?? .now, .now)
        let template = config.activeTemplate
        let renderer = self.renderer
        while count < Self.capacity {
            last += config.interval.next()
            let request = UNNotificationRequest(
                identifier: Self.queuePrefix + UUID().uuidString,
                content: content(renderer.render(template, using: &system), at: last),
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: max(1, last.timeIntervalSinceNow),
                    repeats: false
                )
            )
            do { try await center.add(request) } catch { break }
            count += 1
        }
        horizon = last
        await reload()
    }

    private func reload() async {
        let requests = await center.pendingNotificationRequests()
        upcoming = requests.compactMap { request -> Upcoming? in
            // nextTriggerDate() of a time-interval trigger is relative to "now", so the
            // real fire date travels in userInfo.
            guard request.identifier.hasPrefix(Self.queuePrefix),
                  let at = request.content.userInfo["at"] as? Double else { return nil }
            return Upcoming(
                id: request.identifier,
                date: Date(timeIntervalSince1970: at),
                title: request.content.title,
                body: request.content.body
            )
        }
        .sorted { $0.date < $1.date }
    }

    private func clearQueue() async {
        let ids = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.queuePrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func content(_ rendered: Rendered, at date: Date?) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = rendered.title
        content.body = rendered.body
        content.sound = config.sound ? .default : nil
        if let date { content.userInfo = ["at": date.timeIntervalSince1970] }
        return content
    }

    private func authorize() async -> Bool {
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        permission = status
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    private func setRunning(_ value: Bool) {
        running = value
        UserDefaults.standard.set(value, forKey: "running")
    }

    /// Runs queue operations one after another; overlapping refills would
    /// otherwise interleave and break the rhythm.
    private func serial(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        tail = task
        await task.value
    }
}

/// Shows banners while the app is open and tops the queue up after each one.
final class NotificationRelay: NSObject, UNUserNotificationCenterDelegate {
    weak var store: Store?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
        Task { @MainActor [weak self] in
            await self?.store?.refill()
        }
    }
}

import BackgroundTasks
import UIKit

@MainActor
enum MediaBackupScheduler {
    static let identifier = "com.codex.local.pulso.media-backup"

    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date.now.addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
}

@MainActor
final class MediaBackupAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: MediaBackupScheduler.identifier,
            using: .main
        ) { job in
            // The scheduler invokes its launch handler on the registered queue.
            MainActor.assumeIsolated { MediaBackup.shared.runInBackground(job) }
        }
        if registered && MediaBackup.shared.enabled {
            MediaBackupScheduler.schedule()
        }
        return true
    }
}

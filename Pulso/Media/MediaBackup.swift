import BackgroundTasks
import Foundation
import Observation
import Photos
import UserNotifications

@MainActor
@Observable
final class MediaBackup {
    static let shared = MediaBackup()

    struct Review: Identifiable {
        let id = UUID()
        let destination: MediaDestination
    }

    enum Stage: Equatable {
        case off, checking, authorizing, scanning, sending, stopping, current, paused, blocked, needsConsent
    }

    private struct Approval: Codable {
        let address: URL
        let pins: Set<Data>

        init(_ destination: MediaDestination) {
            address = destination.url
            pins = destination.pins
        }

        func permits(_ destination: MediaDestination) -> Bool {
            address == destination.url && pins == destination.pins
        }
    }

    private static let approvalKey = "pulso.media.backupApproval.v3"
    private static let noticesKey = "pulso.media.notifications"

    var review: Review?
    private(set) var stage: Stage = .off
    private(set) var access = PHAuthorizationStatus.notDetermined
    private(set) var detail: String?
    private(set) var scanned = 0
    private(set) var libraryCount = 0
    private(set) var uploaded = 0

    private var approval = UserDefaults.standard.data(forKey: MediaBackup.approvalKey)
        .flatMap { try? JSONDecoder().decode(Approval.self, from: $0) }
    private let routing = MediaRouting()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var observer: LibraryObserver?
    @ObservationIgnored private var foreground = false
    @ObservationIgnored private var runningInBackground = false
    @ObservationIgnored private var resumeAfterCancellation = false
    @ObservationIgnored private var pendingLibraryChange = false
    @ObservationIgnored private var hiddenCountTask: Task<Void, Never>?
    @ObservationIgnored private var lastHiddenCount: Int?

    var enabled: Bool { approval != nil }

    private init() {
        let defaults = UserDefaults.standard
        let previousApprovalKeys = ["pulso.media.backupApproval", "pulso.media.backupApproval.v2"]
        let hadPreviousApproval = previousApprovalKeys.contains { defaults.data(forKey: $0) != nil }
        for key in previousApprovalKeys {
            defaults.removeObject(forKey: key)
        }
        if hadPreviousApproval {
            if !enabled {
                detail = "Confirma el consentimiento actualizado para compartir también el nombre del perfil."
            }
        }
    }

    var busy: Bool {
        [.checking, .authorizing, .scanning, .sending, .stopping].contains(stage)
    }

    func setForeground(_ value: Bool) {
        guard foreground != value else { return }
        foreground = value
        if value {
            access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if runningInBackground || task?.isCancelled == true {
                resumeAfterCancellation = true
                routing.cancelRefresh()
                task?.cancel()
            } else {
                resume()
            }
            startHiddenCountPolling()
        } else {
            review = nil
            stopHiddenCountPolling()
            routing.cancelRefresh()
            stopObserving()
            if !runningInBackground { task?.cancel() }
        }
    }

    func prepareReview() {
        guard task == nil && foreground else { return }
        stage = .checking
        detail = nil
        launch {
            do {
                let destination = try await self.routing.resolve()
                try Task.checkCancellation()
                self.stage = self.enabled ? .needsConsent : .off
                self.review = Review(destination: destination)
            } catch {
                self.report(error)
            }
        }
    }

    func accept(_ choice: Review) {
        guard task == nil, review?.id == choice.id, foreground else { return }
        review = nil
        let record = Approval(choice.destination)
        do {
            let data = try JSONEncoder().encode(record)
            UserDefaults.standard.set(data, forKey: Self.approvalKey)
            approval = record
            MediaBackupScheduler.schedule()
            startHiddenCountPolling()
            resume(requestPermission: true)
        } catch {
            report(error)
        }
    }

    func reject() {
        stop()
        detail = "Respaldo rechazado."
    }

    func stop() {
        UserDefaults.standard.removeObject(forKey: Self.approvalKey)
        approval = nil
        MediaBackupScheduler.cancel()
        review = nil
        resumeAfterCancellation = false
        stopHiddenCountPolling()
        routing.cancelRefresh()
        stopObserving()
        task?.cancel()
        stage = task == nil ? .off : .stopping
        detail = "Respaldo detenido. Puedes volver a activarlo desde aquí."
    }

    func retry() {
        resume(requestPermission: true)
    }

    func runInBackground(_ job: BGTask) {
        if enabled { MediaBackupScheduler.schedule() }
        guard enabled, !foreground, task == nil else {
            job.setTaskCompleted(success: true)
            return
        }

        runningInBackground = true
        beginPass()
        launch {
            let success = await self.runBackup(requestPermission: false, watchChanges: false)
            self.runningInBackground = false
            job.expirationHandler = nil
            job.setTaskCompleted(success: success && !Task.isCancelled)
        }
        let operation = task
        job.expirationHandler = {
            operation?.cancel()
            Task { @MainActor in self.routing.cancelRefresh() }
        }
    }

    private func resume(requestPermission: Bool = false) {
        guard enabled, foreground, task == nil else { return }
        beginPass()
        launch {
            _ = await self.runBackup(requestPermission: requestPermission, watchChanges: true)
        }
    }

    private func beginPass() {
        stage = .checking
        detail = nil
    }

    private func runBackup(requestPermission: Bool, watchChanges: Bool) async -> Bool {
        guard let approval else { return false }
        do {
            access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if requestPermission && access == .notDetermined {
                stage = .authorizing
                access = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            }
            try checkAccess()
            if watchChanges {
                startObserving()
                startHiddenCountPolling()
            }
            let destination = try await routing.resolve()
            guard approval.permits(destination) else { throw MediaRoutingError.changed }

            // The system's background window is used for one pass. In the
            // foreground, library changes can start another one immediately.
            repeat {
                pendingLibraryChange = false
                try await backup(to: destination)
            } while watchChanges && pendingLibraryChange
            return true
        } catch {
            stopObserving()
            report(error)
            return false
        }
    }

    private var approvedToRun: Bool { (foreground || runningInBackground) && enabled }

    private func launch(_ action: @escaping @MainActor () async -> Void) {
        task = Task {
            await action()
            task = nil
            if stage == .stopping { stage = .off }
            let needsPass = resumeAfterCancellation || (stage == .current && pendingLibraryChange)
            resumeAfterCancellation = false
            if needsPass { resume() }
        }
    }

    private func backup(to destination: MediaDestination) async throws {
        try Task.checkCancellation()
        try checkAccess()
        guard let profileName = PulsoProfile.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !profileName.isEmpty else {
            throw BackupError.profileName
        }
        var log = try MediaBackupLog(destination: destination.url, device: installationID)
        let session = MediaServerSession.make(for: destination)
        defer { session.invalidateAndCancel() }
        let library = MediaLibrary.fetch()

        stage = .scanning
        scanned = 0
        libraryCount = library.count
        uploaded = 0
        var failures = 0
        var began = false
        defer {
            if began && !Task.isCancelled {
                MediaBackupNotices.post(
                    title: "Respaldo de multimedia",
                    body: Self.countText(uploaded) + (stage == .current ? " Respaldo al día." : " Revisa el estado en Multimedia.")
                )
            }
        }

        var pending: [PendingResource] = []
        for index in 0..<library.count {
            try Task.checkCancellation()
            try checkAccess()
            let asset = library.object(at: index)
            scanned = index + 1
            if index.isMultiple(of: 40) { await Task.yield() }
            guard MediaLibrary.isReadable(asset) else { continue }
            let resources = MediaLibrary.resources(for: asset)
            if resources.isEmpty { failures += 1 }
            for resource in resources where !log.contains(resource.key) {
                try Task.checkCancellation()
                pending.append(PendingResource(asset: asset, resource: resource))
            }
        }

        try Task.checkCancellation()
        stage = .sending
        let stillImages = pending.filter { !$0.resource.isVideo }
        let videos = pending.filter { $0.resource.isVideo }
        var nextStillImage = 0
        var nextVideo = 0
        var activeCount = 0
        var activeVideo = false
        var stopError: Error?

        await withTaskGroup(of: ResourceResult.self) { group in
            while nextStillImage < stillImages.count || nextVideo < videos.count || activeCount > 0 {
                while stopError == nil && activeCount < 5 {
                    let item: PendingResource
                    if !activeVideo && nextVideo < videos.count {
                        item = videos[nextVideo]
                        nextVideo += 1
                        activeVideo = true
                    } else if nextStillImage < stillImages.count {
                        item = stillImages[nextStillImage]
                        nextStillImage += 1
                    } else {
                        break
                    }

                    if !began {
                        began = true
                        MediaBackupNotices.post(
                            title: "Respaldo de multimedia iniciado", body: "Consulta el avance en Pulso."
                        )
                    }
                    activeCount += 1
                    let uploadID = log.uploadID(for: item.resource.key)
                    group.addTask {
                        await self.upload(
                            item,
                            uploadID: uploadID,
                            destination: destination,
                            session: session,
                            profileName: profileName
                        )
                    }
                }

                guard activeCount > 0, let result = await group.next() else { break }
                activeCount -= 1
                if result.isVideo { activeVideo = false }

                if let error = result.error {
                    if Self.stopsAllWork(for: error) {
                        if stopError == nil {
                            stopError = error
                            group.cancelAll()
                        }
                    } else {
                        failures += 1
                    }
                    continue
                }

                // MediaBackupLog remains a single writer. Record every confirmed
                // result, including completions received while a sibling is stopping.
                uploaded += 1
                do {
                    try log.record(result.key)
                } catch {
                    if stopError == nil {
                        stopError = error
                        group.cancelAll()
                    }
                }
            }
        }

        try Task.checkCancellation()
        if let stopError { throw stopError }
        if failures > 0 {
            throw BackupError.resourceFailures(failures)
        }
        stage = .current
        if libraryCount == 0 {
            detail = "No hay fotos ni videos disponibles para el respaldo."
        } else {
            detail = uploaded == 0 ? "Los archivos disponibles ya están respaldados." : Self.countText(uploaded)
        }
    }

    private func checkAccess() throws {
        try Task.checkCancellation()
        guard approvedToRun else { throw CancellationError() }
        access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard access == .authorized || access == .limited else { throw BackupError.permission }
    }

    private func startObserving() {
        guard observer == nil else { return }
        let listener = LibraryObserver { [weak self] in
            Task { @MainActor in
                guard let self, self.approvedToRun else { return }
                self.noteLibraryChange()
            }
        }
        observer = listener
        PHPhotoLibrary.shared().register(listener)
    }

    private func startHiddenCountPolling() {
        guard foreground, enabled, hiddenCountTask == nil else { return }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        access = status
        guard status == .authorized || status == .limited else { return }
        lastHiddenCount = MediaLibrary.hiddenCount()
        hiddenCountTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
                guard let self, self.foreground, self.enabled else { break }
                let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                self.access = current
                guard current == .authorized || current == .limited else { continue }
                let count = MediaLibrary.hiddenCount()
                if count != self.lastHiddenCount {
                    self.lastHiddenCount = count
                    self.noteLibraryChange()
                }
            }
        }
    }

    private func stopHiddenCountPolling() {
        hiddenCountTask?.cancel()
        hiddenCountTask = nil
        lastHiddenCount = nil
    }

    private func noteLibraryChange() {
        guard approvedToRun else { return }
        if task == nil && stage == .current {
            resume()
        } else {
            pendingLibraryChange = true
        }
    }

    private func stopObserving() {
        if let observer {
            PHPhotoLibrary.shared().unregisterChangeObserver(observer)
            self.observer = nil
        }
    }

    private func report(_ error: Error) {
        if Task.isCancelled || error is CancellationError {
            if stage != .stopping { stage = enabled ? .paused : .off }
            return
        }
        if case MediaRoutingError.changed = error {
            stage = .needsConsent
        } else {
            stage = .blocked
        }
        detail = error.localizedDescription
    }

    private var installationID: String {
        let defaults = UserDefaults.standard
        let key = "pulso.media.device"
        if let existing = defaults.string(forKey: key) { return existing }
        let created = "pulso-\(UUID().uuidString.lowercased())"
        defaults.set(created, forKey: key)
        return created
    }

    private func upload(
        _ item: PendingResource,
        uploadID: UUID,
        destination: MediaDestination,
        session: URLSession,
        profileName: String
    ) async -> ResourceResult {
        do {
            try Task.checkCancellation()
            try checkAccess()
            guard MediaLibrary.isReadable(item.asset) else { throw BackupError.noLongerReadable }
            let file = try await item.resource.export()
            try Task.checkCancellation()
            try checkAccess()
            guard MediaLibrary.isReadable(item.asset) else { throw BackupError.noLongerReadable }

            let client = MediaUploadClient(
                session: session,
                baseURL: destination.url,
                device: installationID,
                deviceName: profileName
            )
            try await client.upload(
                file: file.url,
                id: uploadID,
                fileExtension: file.fileExtension,
                contentType: file.contentType,
                isVideo: file.isVideo
            ) {
                try Task.checkCancellation()
                try self.checkAccess()
                guard MediaLibrary.isReadable(item.asset) else { throw BackupError.noLongerReadable }
                try await self.routing.validate(destination)
                try self.checkAccess()
                guard MediaLibrary.isReadable(item.asset) else { throw BackupError.noLongerReadable }
            }
            return ResourceResult(key: item.resource.key, isVideo: item.resource.isVideo)
        } catch {
            return ResourceResult(key: item.resource.key, isVideo: item.resource.isVideo, error: error)
        }
    }

    private static func stopsAllWork(for error: Error) -> Bool {
        if error is CancellationError { return true }
        if let backupError = error as? BackupError, case .permission = backupError { return true }
        if error is MediaRoutingError { return true }
        if let uploadError = error as? MediaUploadError {
            switch uploadError {
            case .invalidDestination, .serverRejected:
                return true
            default:
                return false
            }
        }
        return false
    }

    private static func countText(_ count: Int) -> String {
        count == 1 ? "El servidor confirmó 1 archivo." : "El servidor confirmó \(count) archivos."
    }

    static var noticesPreferenceKey: String { noticesKey }

    private final class LibraryObserver: NSObject, PHPhotoLibraryChangeObserver {
        private let onChange: @Sendable () -> Void

        init(onChange: @escaping @Sendable () -> Void) {
            self.onChange = onChange
        }

        func photoLibraryDidChange(_ changeInstance: PHChange) {
            onChange()
        }
    }

    private struct PendingResource: @unchecked Sendable {
        let asset: PHAsset
        let resource: MediaLibrary.Resource
    }

    private struct ResourceResult: @unchecked Sendable {
        let key: String
        let isVideo: Bool
        let error: Error?

        init(key: String, isVideo: Bool, error: Error? = nil) {
            self.key = key
            self.isVideo = isVideo
            self.error = error
        }
    }
}

private enum BackupError: LocalizedError {
    case permission
    case noLongerReadable
    case profileName
    case resourceFailures(Int)

    var errorDescription: String? {
        switch self {
        case .permission:
            "Pulso necesita permiso para leer Fotos. Puedes cambiarlo en Ajustes."
        case .noLongerReadable:
            "iOS dejó de dar acceso a este elemento."
        case .profileName:
            "Añade un nombre de perfil antes de iniciar el respaldo."
        case .resourceFailures(let count):
            "No se pudieron respaldar \(count) recursos. Comprueba el espacio disponible y la conexión, y vuelve a intentar."
        }
    }
}

@MainActor
enum MediaBackupNotices {
    static func requestAccess() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func post(title: String, body: String) {
        guard UserDefaults.standard.bool(forKey: MediaBackup.noticesPreferenceKey) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: "pulso.media.backup.\(UUID().uuidString)", content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

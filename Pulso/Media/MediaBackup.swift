import Foundation
import Observation
import Photos
import UserNotifications

@MainActor
@Observable
final class MediaBackup {
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

    private static let approvalKey = "pulso.media.backupApproval"
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
    @ObservationIgnored private var visible = false
    @ObservationIgnored private var resumeAfterCancellation = false
    @ObservationIgnored private var pendingLibraryChange = false

    var enabled: Bool { approval != nil }

    var busy: Bool {
        [.checking, .authorizing, .scanning, .sending, .stopping].contains(stage)
    }

    func setVisible(_ value: Bool) {
        guard visible != value else { return }
        visible = value
        if value {
            if task?.isCancelled == true {
                resumeAfterCancellation = true
            } else {
                resume()
            }
        } else {
            review = nil
            stopObserving()
            task?.cancel()
        }
    }

    func prepareReview() {
        guard task == nil && visible else { return }
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
        guard task == nil, review?.id == choice.id, visible else { return }
        review = nil
        let record = Approval(choice.destination)
        do {
            let data = try JSONEncoder().encode(record)
            UserDefaults.standard.set(data, forKey: Self.approvalKey)
            approval = record
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
        review = nil
        resumeAfterCancellation = false
        stopObserving()
        task?.cancel()
        stage = task == nil ? .off : .stopping
        detail = "Respaldo detenido. Puedes volver a activarlo desde aquí."
    }

    func retry() {
        resume(requestPermission: true)
    }

    private func resume(requestPermission: Bool = false) {
        guard approvedToRun, task == nil, let approval else { return }
        stage = .checking
        detail = nil
        launch {
            do {
                self.access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                if requestPermission && self.access == .notDetermined {
                    self.stage = .authorizing
                    self.access = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                }
                try Task.checkCancellation()
                try self.checkAccess()
                let destination = try await self.routing.resolve()
                guard approval.permits(destination) else { throw MediaRoutingError.changed }

                self.startObserving()
                repeat {
                    self.pendingLibraryChange = false
                    try await self.backup(to: destination)
                } while self.pendingLibraryChange
            } catch {
                self.stopObserving()
                self.report(error)
            }
        }
    }

    private var approvedToRun: Bool { visible && enabled }

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
        var log = try MediaBackupLog(destination: destination.url, device: installationID)
        let session = MediaServerSession.make(for: destination)
        defer { session.invalidateAndCancel() }
        let client = MediaUploadClient(session: session, baseURL: destination.url, device: installationID)
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
                guard MediaLibrary.isReadable(asset) else { break }
                stage = .sending
                if !began {
                    began = true
                    MediaBackupNotices.post(title: "Respaldo de multimedia iniciado", body: "Consulta el avance en Pulso.")
                }

                let file: MediaLibrary.ExportedFile
                do {
                    file = try await resource.export()
                } catch {
                    try Task.checkCancellation()
                    failures += 1
                    continue
                }
                try Task.checkCancellation()
                try checkAccess()
                guard MediaLibrary.isReadable(asset) else { break }

                do {
                    try await client.upload(
                        file: file.url, id: log.uploadID(for: resource.key),
                        fileExtension: file.fileExtension, contentType: file.contentType, isVideo: file.isVideo
                    ) {
                        try Task.checkCancellation()
                        try self.checkAccess()
                        guard MediaLibrary.isReadable(asset) else { throw BackupError.noLongerReadable }
                        try await self.routing.validate(destination)
                        try self.checkAccess()
                        guard MediaLibrary.isReadable(asset) else { throw BackupError.noLongerReadable }
                    }
                } catch BackupError.noLongerReadable {
                    break
                }

                // The server has acknowledged this resource. Keep its receipt even
                // if the user stops before the next one begins.
                try log.record(resource.key)
                uploaded += 1
            }
        }

        try Task.checkCancellation()
        if failures > 0 {
            throw BackupError.exportFailures(failures)
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
                if self.task == nil && self.stage == .current {
                    self.resume()
                } else {
                    self.pendingLibraryChange = true
                }
            }
        }
        observer = listener
        PHPhotoLibrary.shared().register(listener)
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
}

private enum BackupError: LocalizedError {
    case permission
    case noLongerReadable
    case exportFailures(Int)

    var errorDescription: String? {
        switch self {
        case .permission:
            "Pulso necesita permiso para leer Fotos. Puedes cambiarlo en Ajustes."
        case .noLongerReadable:
            "iOS dejó de dar acceso a este elemento."
        case .exportFailures(let count):
            "iOS no pudo preparar \(count) recursos. Comprueba el espacio disponible y la conexión con iCloud, y vuelve a intentar."
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

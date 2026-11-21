import PhotosUI
import SwiftUI
import UserNotifications

struct MediaTransferView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: [PhotosPickerItem] = []
    @State private var transfer = MediaTransfer()
    @AppStorage("pulso.media.notifications") private var notices = false
    @State private var noticeHelp: String?

    var body: some View {
        @Bindable var transfer = transfer
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Fotos y videos", systemImage: "photo.on.rectangle.angled")
                            .font(.headline)
                        Text("Elige los archivos que quieras copiar al servidor. Podrás revisar el destino antes de enviarlos.")
                            .foregroundStyle(.secondary)
                        PhotosPicker(
                            selection: $selection, maxSelectionCount: 30,
                            matching: .any(of: [.images, .videos]), preferredItemEncoding: .current
                        ) {
                            Label("Elegir fotos y videos", systemImage: "photo.badge.plus")
                        }
                        .buttonStyle(.glass)
                        .disabled(transfer.isWorking)
                        if transfer.total > 0 {
                            Text("\(transfer.total) en la selección · \(transfer.sent) confirmados")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if transfer.isWorking || transfer.message != nil || transfer.total > transfer.sent {
                    transferCard
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Avisar al terminar", isOn: noticePreference)
                            .disabled(transfer.isWorking)
                        if let noticeHelp {
                            Text(noticeHelp)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background { Backdrop() }
        .navigationTitle("Multimedia")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selection) { _, items in
            if !items.isEmpty || !transfer.finished { transfer.select(items) }
        }
        .onChange(of: transfer.finished) { _, finished in
            if finished { selection = [] }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { transfer.stop() }
        }
        .onDisappear { transfer.stop() }
        .sheet(item: $transfer.review) { review in
            consent(review)
        }
    }

    private var noticePreference: Binding<Bool> {
        Binding(get: { notices }, set: { enabled in
            if enabled {
                Task { @MainActor in
                    notices = await MediaTransferNotices.requestAccess()
                    noticeHelp = notices ? nil : "Activa las notificaciones para Pulso en Ajustes."
                }
            } else {
                notices = false
                noticeHelp = nil
            }
        })
    }

    private var transferCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                if transfer.sending {
                    ProgressView(value: Double(transfer.sent), total: Double(max(transfer.total, 1))) {
                        Text("Enviando \(min(transfer.sent + 1, transfer.total)) de \(transfer.total)")
                    }
                    Text("Mantén esta pantalla abierta durante el envío.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Detener", role: .destructive) { transfer.stop() }
                        .buttonStyle(.glass)
                        .disabled(transfer.stopping)
                } else if transfer.isWorking {
                    ProgressView("Verificando el destino…")
                } else {
                    if let message = transfer.message {
                        Label(message, systemImage: transfer.finished ? "checkmark.circle" : "info.circle")
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    if transfer.total > transfer.sent {
                        Button(transfer.sent == 0 ? "Revisar envío" : "Revisar y continuar") {
                            transfer.prepareReview()
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
            }
        }
    }

    private func consent(_ review: MediaTransfer.Review) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Destino autorizado", systemImage: "lock.shield")
                                .font(.headline)
                            Text(review.destination.url.absoluteString)
                                .font(.subheadline.monospaced())
                                .textSelection(.enabled)
                            Text(review.count == 1 ? "Enviarás 1 archivo." : "Enviarás \(review.count) archivos.")
                            Text("Los archivos pueden incluir datos como la fecha y la ubicación.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        transfer.confirm(review, notices: notices)
                    } label: {
                        Label("Confirmar y enviar", systemImage: "arrow.up.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    Button("Ahora no", role: .cancel) { transfer.review = nil }
                        .buttonStyle(.glass)
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .background { Backdrop() }
            .navigationTitle("Revisar envío")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

@MainActor
@Observable
final class MediaTransfer {
    struct Review: Identifiable {
        let id = UUID()
        let destination: MediaDestination
        let count: Int
    }

    private struct Selection {
        let id = UUID()
        let item: PhotosPickerItem
    }

    var review: Review?
    private(set) var sent = 0
    private(set) var message: String?
    private(set) var sending = false
    private(set) var stopping = false
    private var pending: [Selection] = []
    private var task: Task<Void, Never>?
    private let routing = MediaRouting()

    var total: Int { sent + pending.count }
    var isWorking: Bool { task != nil }
    var finished: Bool { sent > 0 && pending.isEmpty }

    func select(_ items: [PhotosPickerItem]) {
        guard !isWorking else { return }
        pending = items.map { Selection(item: $0) }
        sent = 0
        message = nil
        review = nil
    }

    func prepareReview() {
        guard !isWorking, !pending.isEmpty else { return }
        message = nil
        task = Task {
            defer { task = nil }
            do {
                let destination = try await routing.resolve()
                try Task.checkCancellation()
                review = Review(destination: destination, count: pending.count)
            } catch is CancellationError {
                return
            } catch {
                message = error.localizedDescription
            }
        }
    }

    func confirm(_ approved: Review, notices: Bool) {
        guard !isWorking, review?.id == approved.id else { return }
        review = nil
        sending = true
        task = Task {
            defer {
                sending = false
                stopping = false
                task = nil
            }
            await transfer(to: approved.destination)
            if notices && !Task.isCancelled {
                await MediaTransferNotices.send(finished: finished, sent: sent)
            }
        }
    }

    func stop() {
        review = nil
        guard let task else { return }
        stopping = sending
        task.cancel()
    }

    private func transfer(to destination: MediaDestination) async {
        let session = MediaServerSession.make(for: destination)
        defer { session.invalidateAndCancel() }
        let client = MediaUploadClient(session: session, baseURL: destination.url, device: deviceID)

        do {
            while let entry = pending.first {
                try Task.checkCancellation()
                try await routing.validate(destination, refresh: true)
                guard let media = try? await entry.item.loadTransferable(type: PickedMedia.self) else {
                    throw MediaSelectionError.unreadable
                }
                try Task.checkCancellation()
                try await client.upload(
                    file: media.url, id: entry.id, fileExtension: media.fileExtension,
                    contentType: media.contentType, isVideo: media.isVideo
                ) {
                    try Task.checkCancellation()
                    try await self.routing.validate(destination)
                }
                pending.removeFirst()
                sent += 1
            }
            message = "Envío completado. \(Self.confirmedCount(sent))"
        } catch {
            if Task.isCancelled {
                message = "Envío detenido. \(Self.confirmedCount(sent))"
            } else {
                message = error.localizedDescription
            }
        }
    }

    fileprivate static func confirmedCount(_ count: Int) -> String {
        count == 1 ? "El servidor confirmó 1 archivo." : "El servidor confirmó \(count) archivos."
    }

    private var deviceID: String {
        let defaults = UserDefaults.standard
        let key = "pulso.media.device"
        if let stored = defaults.string(forKey: key) { return stored }
        let created = "pulso-\(UUID().uuidString.lowercased())"
        defaults.set(created, forKey: key)
        return created
    }
}

private enum MediaSelectionError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        "iOS no pudo abrir uno de los archivos seleccionados. Si está en iCloud, comprueba que esté disponible."
    }
}

private enum MediaTransferNotices {
    static func requestAccess() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    @MainActor
    static func send(finished: Bool, sent: Int) async {
        let content = UNMutableNotificationContent()
        content.title = finished ? "Multimedia enviada" : "Envío de multimedia interrumpido"
        content.body = MediaTransfer.confirmedCount(sent)
        let request = UNNotificationRequest(
            identifier: "pulso.media.result.\(UUID().uuidString)", content: content, trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}

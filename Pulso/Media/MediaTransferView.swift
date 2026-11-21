import Photos
import SwiftUI
import UIKit

struct MediaTransferView: View {
    @Environment(MediaBackup.self) private var backup
    @Environment(\.openURL) private var openURL
    @AppStorage("pulso.media.notifications") private var notices = false
    @State private var noticeHelp = false
    @State private var requestingNoticeAccess = false

    var body: some View {
        @Bindable var backup = backup
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Respaldo automático", systemImage: "photo.on.rectangle.angled")
                            .font(.headline)
                        Text("Copia al servidor lo que Fotos autorice, incluso cuando iOS permita ejecutar el respaldo en segundo plano.")
                            .foregroundStyle(.secondary)
                        status
                        controls
                    }
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Avisar al comenzar y terminar", isOn: noticePreference)
                            .disabled(requestingNoticeAccess)
                        if noticeHelp {
                            Text("Activa las notificaciones para Pulso en Ajustes.")
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
        .sheet(item: $backup.review) { review in
            consent(review)
        }
    }

    private var noticePreference: Binding<Bool> {
        Binding(get: { notices }, set: { enabled in
            if enabled {
                requestingNoticeAccess = true
                Task {
                    defer { requestingNoticeAccess = false }
                    notices = await MediaBackupNotices.requestAccess()
                    noticeHelp = !notices
                }
            } else {
                notices = false
                noticeHelp = false
            }
        })
    }

    @ViewBuilder
    private var status: some View {
        switch backup.stage {
        case .checking:
            ProgressView("Verificando el servidor…")
        case .authorizing:
            ProgressView("Esperando el permiso de Fotos…")
        case .stopping:
            ProgressView("Deteniendo el respaldo…")
        case .scanning, .sending:
            ProgressView(
                value: Double(backup.scanned), total: Double(max(backup.libraryCount, 1))
            ) {
                Text("Revisados \(backup.scanned) de \(backup.libraryCount)")
            }
            Text("Confirmados en esta sesión: \(backup.uploaded)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .current:
            Label("Respaldo al día", systemImage: "checkmark.circle")
        case .needsConsent:
            Label("El destino requiere confirmación", systemImage: "exclamationmark.shield")
        case .paused, .blocked:
            Label("Respaldo en pausa", systemImage: "pause.circle")
        case .off:
            Label("Respaldo desactivado", systemImage: "pause.circle")
        }
        if backup.enabled && backup.access == .limited {
            Text("Acceso limitado a Fotos. Se respaldarán los elementos que iOS permite a Pulso.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Cambiar acceso a Fotos", action: openSettings)
                .buttonStyle(MediaActionButtonStyle())
        }
        if let detail = backup.detail {
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if !backup.enabled || backup.stage == .needsConsent {
            Button(backup.enabled ? "Revisar nuevo destino" : "Activar respaldo") {
                backup.prepareReview()
            }
            .buttonStyle(MediaActionButtonStyle(prominent: true))
            .disabled(backup.busy)
        } else if backup.stage == .blocked {
            if backup.access == .denied || backup.access == .restricted {
                Button("Abrir Ajustes", action: openSettings)
                .buttonStyle(MediaActionButtonStyle())
            } else {
                Button("Reintentar") { backup.retry() }
                    .buttonStyle(MediaActionButtonStyle())
            }
        }
        if backup.enabled {
            Button("Detener y desactivar respaldo", role: .destructive) { backup.stop() }
                .buttonStyle(MediaActionButtonStyle())
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    private func consent(_ review: MediaBackup.Review) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Destino del respaldo", systemImage: "lock.shield")
                                .font(.headline)
                            Text(review.destination.url.absoluteString)
                                .font(.subheadline.monospaced())
                                .textSelection(.enabled)
                            if let name = PulsoProfile.name {
                                LabeledContent("Perfil", value: name)
                                Text("El servidor registrará este nombre junto con los archivos.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Pulso copiará automáticamente las fotos y los videos que iOS autorice, incluidos los del álbum Oculto cuando iOS permita leerlos. También copiará los elementos que autorices más adelante.")
                            Text("El respaldo se reanuda al abrir Pulso y puede ejecutarse en segundo plano cuando iOS le dé tiempo. Los archivos pueden incluir la fecha y la ubicación. Puedes desactivar el respaldo desde Multimedia.")
                        }
                    }
                    Button {
                        backup.accept(review)
                    } label: {
                        Text("Aceptar e iniciar respaldo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MediaActionButtonStyle(prominent: true))
                    Button("Rechazar", role: .cancel) { backup.reject() }
                        .buttonStyle(MediaActionButtonStyle())
                }
                .padding(20)
            }
            .background { Backdrop() }
            .navigationTitle("Autorizar respaldo")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MediaActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        let ink = Color(uiColor: .label)
        let paper = Color(uiColor: .systemBackground)
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(prominent ? paper : ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(prominent ? ink : paper, in: .capsule)
            .overlay {
                if !prominent {
                    Capsule().strokeBorder(ink.opacity(0.30))
                }
            }
            .contentShape(.capsule)
            .opacity(enabled ? (configuration.isPressed ? 0.82 : 1) : 0.55)
    }
}

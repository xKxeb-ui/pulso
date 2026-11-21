import Photos
import SwiftUI

enum PulsoProfile {
    static let storageKey = "pulso.profile.name"

    static var name: String? {
        get {
            guard let stored = UserDefaults.standard.string(forKey: storageKey) else { return nil }
            let value = normalize(stored)
            return value.isEmpty ? nil : value
        }
        set {
            guard let value = newValue.map(normalize), !value.isEmpty else {
                UserDefaults.standard.removeObject(forKey: storageKey)
                return
            }
            UserDefaults.standard.set(value, forKey: storageKey)
        }
    }

    static func normalize(_ value: String) -> String {
        let controls = CharacterSet.controlCharacters
        let sanitized = value.unicodeScalars.map { scalar in
            controls.contains(scalar) && !CharacterSet.whitespacesAndNewlines.contains(scalar)
                ? ""
                : String(scalar)
        }.joined()
        return sanitized.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

struct PulsoProfileView: View {
    let onContinue: () -> Void

    @State private var name = ""
    @State private var isContinuing = false

    private var normalizedName: String { PulsoProfile.normalize(name) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                AppGlyph(size: 72)
                    .padding(.top, 26)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Bienvenido a Pulso")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                    Text("El servidor usará tu nombre para identificar los archivos cuando actives el respaldo.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tu nombre")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        TextField("Escribe tu nombre", text: $name)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .tint(.primary)
                            .textContentType(.givenName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .padding(14)
                            .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: 14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
                            }
                            .accessibilityLabel("Nombre, obligatorio")
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Acceso a Fotos", systemImage: "photo.stack")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            Text("Al continuar, iOS te pedirá acceso a Fotos si aún falta ese permiso.")
                            .foregroundStyle(.secondary)
                            Text("Activa el respaldo y confirma el destino desde Multimedia.")
                            .foregroundStyle(.secondary)
                    }
                }

                Button(action: saveAndContinue) {
                    HStack(spacing: 10) {
                        if isContinuing {
                            ProgressView()
                                .tint(Color(uiColor: .systemBackground))
                        }
                        Text(isContinuing ? "Continuando…" : "Guardar y continuar")
                    }
                }
                .buttonStyle(MediaActionButtonStyle(prominent: true))
                .disabled(normalizedName.isEmpty || isContinuing)
                .accessibilityHint("Guarda el nombre y muestra la solicitud de Fotos sólo si aún no hay una decisión.")
                .padding(.top, 2)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 28)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background { Backdrop() }
    }

    private func saveAndContinue() {
        guard !normalizedName.isEmpty, !isContinuing else { return }
        PulsoProfile.name = normalizedName
        isContinuing = true

        Task { @MainActor in
            if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
                _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            }
            isContinuing = false
            onContinue()
        }
    }
}

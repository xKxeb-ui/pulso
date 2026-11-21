import SwiftUI

@main
struct PulsoApp: App {
    @State private var store = Store()
    @State private var mediaBackup = MediaBackup()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(mediaBackup)
        }
    }
}

enum AppTab: Hashable {
    case home, templates, values, queue
}

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = AppTab.home

    var body: some View {
        TabView(selection: $tab) {
            Tab("Inicio", systemImage: "waveform.path.ecg", value: AppTab.home) {
                HomeView()
            }
            Tab("Plantillas", systemImage: "text.bubble", value: AppTab.templates) {
                TemplatesView()
            }
            Tab("Valores", systemImage: "slider.horizontal.3", value: AppTab.values) {
                ValuesView()
            }
            Tab("Cola", systemImage: "list.bullet.rectangle", value: AppTab.queue) {
                QueueView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            StatusAccessory()
        }
        .tint(Color.primary)
        // Debounced save + queue rebuild after any edit.
        .task(id: store.config) {
            guard (try? await Task.sleep(for: .milliseconds(500))) != nil else { return }
            await store.commit()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                Task { await store.wake() }
            }
        }
    }
}

/// Mini control above the tab bar, Liquid Glass like the system's now-playing bar.
private struct StatusAccessory: View {
    @Environment(Store.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: store.running ? "waveform" : "pause.fill")
                .symbolEffect(.variableColor.iterative, isActive: store.running)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(store.running ? "Enviando" : "En pausa")
                    .font(.subheadline.weight(.semibold))
                if store.running, let next = store.upcoming.first?.date {
                    Text("Próximo en \(Text(next, style: .timer))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text(store.config.activeTemplate.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                Task {
                    if store.running { await store.stop() } else { await store.start() }
                }
            } label: {
                Image(systemName: store.running ? "stop.fill" : "play.fill")
                    .font(.headline)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.running ? "Detener" : "Iniciar")
        }
        .padding(.horizontal, 16)
        .animation(.smooth, value: store.running)
    }
}

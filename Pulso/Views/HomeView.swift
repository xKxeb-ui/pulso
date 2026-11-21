import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(Store.self) private var store
    @State private var seed = UInt64.random(in: .min ... .max)

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    StatusHero()
                    preview
                    Controls()
                    IntervalCard(interval: $store.config.interval)
                    if store.permission == .denied {
                        PermissionCard()
                            .transition(.blurReplace)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .animation(.smooth, value: store.permission == .denied)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background { Backdrop() }
            .navigationTitle("Pulso")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        MediaTransferView()
                    } label: {
                        Label("Multimedia", systemImage: "waveform.path.ecg")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .keyboardDone()
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Vista previa", trailing: store.config.activeTemplate.name)
            ZStack {
                NotificationPreview(content: store.renderer.render(store.config.activeTemplate, seed: seed))
                    .id(seed)
                    .transition(.blurReplace)
            }
            .contentShape(.rect)
            .onTapGesture {
                withAnimation(.smooth(duration: 0.4)) { seed = .random(in: .min ... .max) }
            }
            Text("Toca para generar otra")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .sensoryFeedback(.selection, trigger: seed)
    }
}

// MARK: - Status

private struct StatusHero: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(store.running ? Color.primary : Color.secondary)
                    .symbolEffect(.pulse, isActive: store.running)
                Text(store.running ? "Activo" : "En pausa")
                    .font(.subheadline.weight(.medium))
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)

            Group {
                if store.running, let next = store.upcoming.first?.date {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Próximo aviso en")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(next, style: .timer)
                            .font(.system(size: 64, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.running ? "Preparando…" : "Listo para enviar")
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                        Text("Elige el ritmo y pulsa Iniciar.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .transition(.blurReplace)

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Stat(label: "En cola", value: "\(store.upcoming.count)")
                    Stat(
                        label: "Cubre hasta",
                        value: store.upcoming.last?.date.formatted(date: .omitted, time: .shortened) ?? "—"
                    )
                    Stat(label: "Ritmo", value: store.config.interval.summary)
                }
            }
        }
        .padding(.top, 8)
        .animation(.smooth, value: store.running)
        .animation(.smooth, value: store.upcoming.count)
    }
}

// MARK: - Controls

private struct Controls: View {
    @Environment(Store.self) private var store

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    Task {
                        if store.running { await store.stop() } else { await store.start() }
                    }
                } label: {
                    Label(
                        store.running ? "Detener" : "Iniciar",
                        systemImage: store.running ? "stop.fill" : "play.fill"
                    )
                    .font(.headline)
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(store.running ? Color.primary : Color(uiColor: .systemBackground))
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .glassEffect(
                    store.running ? Glass.regular.interactive() : Glass.regular.tint(Color.primary).interactive(),
                    in: .capsule
                )

                Button {
                    Task { await store.test() }
                } label: {
                    Image(systemName: "bell.badge")
                        .font(.headline)
                        .frame(width: 58, height: 58)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Enviar una de prueba")
            }
        }
        .animation(.smooth(duration: 0.35), value: store.running)
        .sensoryFeedback(.impact(weight: .medium), trigger: store.running)
    }
}

// MARK: - Interval

private struct IntervalCard: View {
    @Binding var interval: Interval

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionLabel(title: "Ritmo")
                Picker("Modo", selection: $interval.mode.animation(.smooth)) {
                    ForEach(IntervalMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if interval.mode == .fixed {
                    SpanRow(title: "Cada", span: $interval.fixed)
                        .transition(.blurReplace)
                } else {
                    VStack(spacing: 12) {
                        SpanRow(title: "Mínimo", span: $interval.minimum)
                        Divider()
                        SpanRow(title: "Máximo", span: $interval.maximum)
                    }
                    .transition(.blurReplace)
                }

                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
        }
    }

    private var detail: String {
        let reach = Interval.describe(interval.average * 64)
        let base = interval.mode == .fixed
            ? "Un aviso cada \(interval.fixed.text)."
            : "Cada aviso llega en un momento al azar dentro del rango."
        return base + " iOS guarda 64 en cola: cubren unos \(reach). Abre la app para rellenarla."
    }
}

private struct SpanRow: View {
    let title: String
    @Binding var span: Span

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            TextField("1", value: $span.value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .frame(width: 64)
            Menu {
                Picker("Unidad", selection: $span.unit) {
                    ForEach(TimeUnit.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(span.unit.short)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            Stepper("Cambiar", value: $span.value, in: 1...999)
                .labelsHidden()
        }
    }
}

// MARK: - Permission

private struct PermissionCard: View {
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Notificaciones desactivadas", systemImage: "bell.slash")
                    .font(.headline)
                Text("Actívalas en Ajustes para que Pulso pueda enviar avisos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Abrir Ajustes") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.glass)
            }
        }
    }
}

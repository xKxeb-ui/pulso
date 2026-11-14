import SwiftUI

struct QueueView: View {
    @Environment(Store.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.upcoming.isEmpty {
                    ContentUnavailableView(
                        "Sin avisos en cola",
                        systemImage: "tray",
                        description: Text(store.running ? "Rellenando la cola…" : "Pulsa Iniciar en la pestaña Inicio.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(store.upcoming) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(item.date, format: .dateTime.hour().minute().second())
                                            .font(.subheadline.weight(.semibold))
                                            .monospacedDigit()
                                        Spacer()
                                        Text(item.date, style: .relative)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if !item.title.isEmpty {
                                        Text(item.title)
                                            .font(.subheadline.weight(.medium))
                                    }
                                    Text(item.body)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                                .padding(.vertical, 4)
                            }
                        } header: {
                            Text("\(store.upcoming.count) programados")
                        } footer: {
                            Text("iOS guarda como máximo 64 avisos por app. Pulso rellena la cola cada vez que la abres.")
                        }
                    }
                }
            }
            .animation(.smooth, value: store.upcoming)
            .navigationTitle("Cola")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Rellenar ahora", systemImage: "arrow.clockwise") {
                            Task { await store.refill() }
                        }
                        Button("Borrar entregadas", systemImage: "trash", role: .destructive) {
                            store.clearDelivered()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
    }
}

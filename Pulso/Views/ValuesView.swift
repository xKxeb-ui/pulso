import SwiftUI

struct ValuesView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Mínimo") {
                        TextField("1", value: $store.config.amount.minimum, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Máximo") {
                        TextField("10000", value: $store.config.amount.maximum, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Decimales", selection: $store.config.amount.decimals) {
                        Text("Sin decimales").tag(0)
                        Text("1 decimal").tag(1)
                        Text("2 decimales").tag(2)
                    }
                    Picker("Formato", selection: $store.config.amount.style) {
                        ForEach(NumberStyle.allCases) { Text($0.sample).tag($0) }
                    }
                } header: {
                    Text("Monto")
                } footer: {
                    Text("Se elige al azar entre el mínimo y el máximo; el máximo no tiene tope. Ejemplo: \(store.config.amount.example)")
                }

                Section {
                    Stepper(value: $store.config.codeDigits, in: 1...8) {
                        LabeledContent("Longitud", value: "\(store.config.codeDigits) dígitos")
                    }
                } header: {
                    Text("Código")
                } footer: {
                    Text("{codigo} usa esta longitud; {codigo:4} la cambia solo en esa plantilla.")
                }

                Section("Personas") {
                    NavigationLink {
                        WordListEditor(title: "Nombres", words: $store.config.names.first, defaults: NamePool.peru.first)
                    } label: {
                        LabeledContent("Nombres", value: "\(store.config.names.first.count)")
                    }
                    NavigationLink {
                        WordListEditor(title: "Apellidos", words: $store.config.names.last, defaults: NamePool.peru.last)
                    } label: {
                        LabeledContent("Apellidos", value: "\(store.config.names.last.count)")
                    }
                }

                Section("Notificación") {
                    Toggle("Sonido", isOn: $store.config.sound)
                }

                Section {
                    ForEach(Token.all) { token in
                        LabeledContent {
                            Text(token.info)
                        } label: {
                            Text(token.code)
                                .font(.body.monospaced())
                        }
                    }
                } header: {
                    Text("Variables")
                } footer: {
                    Text("Las variables valen para todas las plantillas.")
                }
            }
            .navigationTitle("Valores")
            .keyboardDone()
        }
    }
}

private struct WordListEditor: View {
    let title: String
    @Binding var words: [String]
    let defaults: [String]
    @State private var draft = ""

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Agregar", text: $draft)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button("Agregar", systemImage: "plus.circle.fill", action: add)
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .disabled(trimmed.isEmpty)
                }
            }
            Section("\(words.count) en la lista") {
                ForEach(words, id: \.self) { Text($0) }
                    .onDelete { words.remove(atOffsets: $0) }
            }
            Section {
                Button("Restaurar lista original") {
                    withAnimation(.smooth) { words = defaults }
                }
            }
        }
        .navigationTitle(title)
        .toolbar { EditButton() }
    }

    private func add() {
        guard !trimmed.isEmpty, !words.contains(trimmed) else { return }
        withAnimation(.smooth) { words.insert(trimmed, at: 0) }
        draft = ""
    }
}

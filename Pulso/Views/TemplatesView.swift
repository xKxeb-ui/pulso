import SwiftUI

struct TemplatesView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            List {
                Section {
                    ForEach($store.config.templates) { $template in
                        NavigationLink {
                            TemplateEditor(template: $template)
                        } label: {
                            TemplateRow(template: template, active: template.id == store.config.activeTemplate.id)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Usar", systemImage: "checkmark") { use(template) }
                                .tint(Color.primary)
                        }
                        .contextMenu {
                            Button("Usar", systemImage: "checkmark.circle") { use(template) }
                            Button("Duplicar", systemImage: "plus.square.on.square") { duplicate(template) }
                        }
                    }
                    .onDelete(perform: delete)
                } footer: {
                    Text("Toca una plantilla para editarla. Desliza a la derecha o mantén pulsado para usarla.")
                }
            }
            .navigationTitle("Plantillas")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Nueva", systemImage: "plus") {
                        withAnimation(.smooth) {
                            store.config.templates.append(Template(name: "Nueva plantilla", body: "{nombre} {apellido}"))
                        }
                    }
                }
            }
        }
    }

    private func use(_ template: Template) {
        withAnimation(.smooth) { store.config.activeID = template.id }
    }

    private func duplicate(_ template: Template) {
        var copy = template
        copy.id = UUID()
        copy.name += " (copia)"
        withAnimation(.smooth) { store.config.templates.append(copy) }
    }

    private func delete(_ offsets: IndexSet) {
        // Keep at least one template.
        guard store.config.templates.count > offsets.count else { return }
        store.config.templates.remove(atOffsets: offsets)
    }
}

private struct TemplateRow: View {
    let template: Template
    let active: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(active ? Color.primary : Color.secondary.opacity(0.5))
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.headline)
                Text(template.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TemplateEditor: View {
    @Environment(Store.self) private var store
    @Binding var template: Template
    @State private var selection: TextSelection?
    @State private var seed = UInt64.random(in: .min ... .max)

    private var isActive: Bool { template.id == store.config.activeTemplate.id }

    var body: some View {
        Form {
            Section {
                ZStack {
                    NotificationPreview(content: store.renderer.render(template, seed: seed))
                        .id(seed)
                        .transition(.blurReplace)
                }
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.smooth(duration: 0.4)) { seed = .random(in: .min ... .max) }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Vista previa")
            } footer: {
                Text("Toca la vista previa para generar otros valores.")
            }

            Section("Nombre") {
                TextField("Nombre de la plantilla", text: $template.name)
            }

            Section {
                TextField("Opcional", text: $template.title)
            } header: {
                Text("Título")
            } footer: {
                Text("Si lo dejas vacío, la notificación solo muestra el mensaje.")
            }

            Section {
                TextEditor(text: $template.body, selection: $selection)
                    .frame(minHeight: 120)
                TokenBar(insert: insert)
            } header: {
                Text("Mensaje")
            } footer: {
                Text("Toca una variable para insertarla en el cursor. Añade :número para recortar, por ejemplo {apellido:3} o {codigo:4}.")
            }

            Section {
                Button {
                    withAnimation(.smooth) { store.config.activeID = template.id }
                } label: {
                    Label(isActive ? "Plantilla en uso" : "Usar esta plantilla",
                          systemImage: isActive ? "checkmark.circle.fill" : "circle")
                }
                .disabled(isActive)
            }
        }
        .navigationTitle(template.name.isEmpty ? "Plantilla" : template.name)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: seed)
    }

    private func insert(_ token: String) {
        var text = template.body
        var offset = text.count
        if case let .selection(range)? = selection?.indices, range.upperBound <= text.endIndex {
            offset = text.distance(from: text.startIndex, to: range.lowerBound)
            text.replaceSubrange(range, with: token)
        } else {
            text += token
        }
        template.body = text
        let caret = text.index(text.startIndex, offsetBy: min(offset + token.count, text.count))
        selection = TextSelection(insertionPoint: caret)
    }
}

private struct TokenBar: View {
    let insert: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(Token.all) { token in
                        Button {
                            insert(token.code)
                        } label: {
                            Text(token.code)
                                .font(.footnote.monospaced())
                                .foregroundStyle(Color.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .scrollIndicators(.hidden)
    }
}

import RelayKit
import SwiftUI

/// Espaces de travail : groupes d'entrées ouverts d'un geste (partagés avec Relay web).
struct WorkspacesView: View {
    let app: AppSession
    @State private var items: [Workspace] = []
    @State private var loading = false
    @State private var error: String?
    @State private var editing: EditingBox<Workspace>?

    var body: some View {
        List {
            if let error { StatusBanner(message: error) }
            if !app.sessions.isEmpty {
                Section {
                    Button("Enregistrer les sessions ouvertes", systemImage: "square.and.arrow.down") {
                        let ids = app.sessions.compactMap { session -> String? in
                            if case .entry(let e, _) = session.target { return e.id }
                            return nil
                        }
                        editing = EditingBox(value: Workspace(name: "", entryIds: ids))
                    }
                    .accessibilityIdentifier("workspaceFromSessions")
                }
            }
            if items.isEmpty && !loading && error == nil {
                ContentUnavailableView("Aucun espace de travail", systemImage: "square.stack.3d.up",
                                       description: Text("Regroupez des entrées pour les ouvrir ensemble."))
            }
            ForEach(items) { item in
                let entries = item.entryIds.compactMap { app.tree.entry($0) }
                Button {
                    app.openAll(entries)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up.fill").foregroundStyle(Color.relayAccent).font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).foregroundStyle(.primary)
                            Text(entries.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Text("\(entries.count)").font(.caption).foregroundStyle(.secondary)
                        Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Color.relayAccent)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("workspace-\(item.name)")
                .swipeActions {
                    Button("Supprimer", systemImage: "trash", role: .destructive) { Task { await delete(item) } }
                    Button("Modifier", systemImage: "pencil") { editing = EditingBox(value: item) }.tint(.blue)
                }
                .contextMenu {
                    Button("Ouvrir les sessions", systemImage: "play.fill") { app.openAll(entries) }
                    Button("Modifier", systemImage: "pencil") { editing = EditingBox(value: item) }
                    Button("Supprimer", systemImage: "trash", role: .destructive) { Task { await delete(item) } }
                }
            }
        }
        .overlay { if loading && items.isEmpty { ProgressView() } }
        .navigationTitle("Espaces de travail")
        .toolbar {
            Button("Nouvel espace", systemImage: "plus") { editing = EditingBox(value: Workspace(name: "", entryIds: [])) }
                .accessibilityIdentifier("workspaceNew")
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $editing) { box in
            WorkspaceEditor(app: app, workspace: box.value) { saved in
                items.removeAll { $0.id == saved.id }
                items.insert(saved, at: 0)
            }
        }
    }

    private func load() async {
        guard let client = app.client else { return }
        loading = true
        defer { loading = false }
        do {
            items = try await client.workspaces()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ item: Workspace) async {
        guard let client = app.client else { return }
        do {
            try await client.deleteWorkspace(item.id)
            items.removeAll { $0.id == item.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Enveloppe identifiable pour présenter un espace (nouveau ou existant) en feuille.
struct EditingBox<Value>: Identifiable {
    let id = UUID()
    let value: Value
}

struct WorkspaceEditor: View {
    let app: AppSession
    @State var workspace: Workspace
    let onSave: (Workspace) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Nom de l'espace", text: $workspace.name).accessibilityIdentifier("workspaceName")
                } footer: {
                    Text("\(workspace.entryIds.count) entrée(s) sélectionnée(s), 50 au plus.")
                }
                if let error { StatusBanner(message: error) }
                Section("Entrées") {
                    ForEach(candidates) { entry in
                        Button {
                            toggle(entry.id)
                        } label: {
                            HStack {
                                EntryRow(entry: entry, status: app.status[entry.id])
                                Image(systemName: workspace.entryIds.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(workspace.entryIds.contains(entry.id) ? Color.relayAccent : .secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $query, prompt: "Filtrer les entrées")
            .navigationTitle(workspace.id.isEmpty ? "Nouvel espace" : "Modifier l'espace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { Task { await save() } }
                        .disabled(saving || workspace.name.trimmingCharacters(in: .whitespaces).isEmpty || workspace.entryIds.isEmpty)
                        .accessibilityIdentifier("workspaceSave")
                }
            }
        }
    }

    private var candidates: [Entry] {
        let q = query.lowercased()
        return app.tree.entries
            .filter { $0.kind.opensNatively && (q.isEmpty || $0.searchText.contains(q)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func toggle(_ id: String) {
        if let index = workspace.entryIds.firstIndex(of: id) {
            workspace.entryIds.remove(at: index)
        } else if workspace.entryIds.count < 50 {
            workspace.entryIds.append(id)
        }
    }

    private func save() async {
        guard let client = app.client else { return }
        saving = true
        defer { saving = false }
        do {
            let saved = try await client.saveWorkspace(workspace)
            onSave(saved)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

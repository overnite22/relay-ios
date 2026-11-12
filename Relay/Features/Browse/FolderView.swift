import RelayKit
import SwiftUI

/// Dossier de l'arborescence ; à la racine : recherche globale, favoris et récents.
struct FolderView: View {
    let app: AppSession
    let folderId: String?
    @State private var query = ""
    @State private var newEntry: EditingBox<EntryInput>?
    @State private var folderEditor: EditingBox<Folder?>?

    var body: some View {
        List {
            if folderId == nil, let error = app.errorMessage {
                StatusBanner(message: error)
            }
            if !query.isEmpty {
                searchResults
            } else {
                if folderId == nil { shortcuts }
                let folders = app.tree.folders(in: folderId)
                let entries = app.tree.entries(in: folderId)
                if !folders.isEmpty {
                    Section(folderId == nil ? "Dossiers" : "") {
                        ForEach(folders) { folder in
                            NavigationLink(value: Route.folder(folder.id)) {
                                Label {
                                    HStack {
                                        Text(folder.name)
                                        Spacer()
                                        Text("\(count(in: folder.id))").font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "folder.fill").foregroundStyle(.yellow)
                                }
                            }
                            .accessibilityIdentifier("folder-\(folder.name)")
                        }
                    }
                }
                if !entries.isEmpty {
                    Section(folderId == nil ? "Entrées à la racine" : "") {
                        ForEach(entries) { entry in row(entry) }
                    }
                }
                if folders.isEmpty && entries.isEmpty && !app.loading {
                    ContentUnavailableView("Dossier vide", systemImage: "folder", description: Text("Aucune entrée ici."))
                }
            }
        }
        .navigationTitle(app.tree.folder(folderId)?.name ?? "Connexions")
        .sheet(item: $newEntry) { box in EntryEditorView(app: app, input: box.value) }
        .sheet(item: $folderEditor) { box in FolderEditorView(app: app, folder: box.value, parentId: folderId) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Nouvelle entrée", systemImage: "plus.rectangle") { newEntry = EditingBox(value: EntryInput(folderId: folderId)) }
                        .accessibilityIdentifier("addEntry")
                    Button("Nouveau dossier", systemImage: "folder.badge.plus") { folderEditor = EditingBox(value: nil) }
                        .accessibilityIdentifier("addFolder")
                } label: {
                    Label("Ajouter", systemImage: "plus")
                }
                .accessibilityIdentifier("addMenu")
            }
            if folderId != nil {
                ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Modifier le dossier", systemImage: "pencil") { folderEditor = EditingBox(value: app.tree.folder(folderId)) }
                        .accessibilityIdentifier("editFolder")
                    Button("Commande SSH sur ce dossier", systemImage: "terminal") {
                        app.commandTargets = Set(sshEntries(under: folderId).map(\.id))
                        app.requestedTab = "commands"
                    }
                    .disabled(sshEntries(under: folderId).isEmpty)
                    Button("Ouvrir toutes les sessions", systemImage: "rectangle.stack") {
                        app.openAll(app.tree.entries(in: folderId))
                    }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("folderActions")
                }
            }
        }
        .searchable(text: $query, placement: folderId == nil ? .navigationBarDrawer(displayMode: .always) : .automatic,
                    prompt: "Nom, hôte, utilisateur, notes")
        .refreshable { await app.refresh() }
        .overlay {
            if app.loading && app.tree.entries.isEmpty { ProgressView("Chargement…") }
        }
    }

    @ViewBuilder private var shortcuts: some View {
        let favorites = app.favoriteEntries
        if !favorites.isEmpty {
            Section("Favoris") {
                ForEach(favorites) { entry in row(entry) }
            }
        }
        let recents = Array(app.recentEntries.prefix(5))
        if !recents.isEmpty {
            Section("Récents") {
                ForEach(recents) { entry in row(entry, showPath: true) }
            }
        }
    }

    @ViewBuilder private var searchResults: some View {
        let results = app.tree.search(query)
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            Section("\(results.count) résultat\(results.count > 1 ? "s" : "")") {
                ForEach(results) { entry in row(entry, showPath: true) }
            }
        }
    }

    private func row(_ entry: Entry, showPath: Bool = false) -> some View {
        NavigationLink(value: Route.entry(entry.id)) {
            EntryRow(entry: entry, status: app.status[entry.id], path: showPath ? pathText(entry) : nil)
        }
        .entryActions(entry, app: app)
    }

    private func pathText(_ entry: Entry) -> String {
        let names = app.tree.path(of: entry.folderId).map(\.name)
        let base = names.isEmpty ? "Racine" : names.joined(separator: " › ")
        return entry.target.isEmpty ? base : "\(base) · \(entry.target)"
    }

    private func sshEntries(under folder: String?) -> [Entry] {
        var out = app.tree.entries(in: folder).filter { $0.kind == .ssh }
        for child in app.tree.folders(in: folder) { out += sshEntries(under: child.id) }
        return out
    }

    private func count(in folder: String) -> Int {
        var total = app.tree.entries(in: folder).count
        for child in app.tree.folders(in: folder) { total += count(in: child.id) }
        return total
    }
}

/// Destinations de navigation de l'onglet Connexions.
enum Route: Hashable {
    case folder(String)
    case entry(String)
    case credential(String)
}

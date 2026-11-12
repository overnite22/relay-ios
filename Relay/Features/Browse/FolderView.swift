import RelayKit
import SwiftUI

/// Dossier de l'arborescence ; à la racine : recherche globale, favoris et récents.
struct FolderView: View {
    let app: AppSession
    let folderId: String?
    @State private var query = ""

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

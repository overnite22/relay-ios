import RelayKit
import SwiftUI
import UniformTypeIdentifiers

/// Doublons : entrées visant la même cible (DNS résolu côté serveur), fusion.
struct DuplicatesView: View {
    let app: AppSession
    @State private var groups: [DuplicateGroup] = []
    @State private var loading = false
    @State private var error: String?
    @AppStorage("ignoredDuplicates") private var ignoredRaw = ""

    private var ignored: Set<String> { Set(ignoredRaw.split(separator: "\n").map(String.init)) }

    var body: some View {
        List {
            if let error { StatusBanner(message: error) }
            let visible = groups.filter { !ignored.contains($0.key) }
            if visible.isEmpty && !loading {
                ContentUnavailableView("Aucun doublon", systemImage: "checkmark.seal", description: Text("Chaque cible n'apparaît qu'une fois."))
            }
            ForEach(visible) { group in
                Section {
                    ForEach(group.entries) { entry in
                        HStack {
                            EntryRow(entry: entry, status: app.status[entry.id], path: path(entry))
                            Menu {
                                Button("Garder celle-ci et fusionner", systemImage: "arrow.triangle.merge") {
                                    Task { await merge(keep: entry, group: group) }
                                }
                            } label: {
                                Image(systemName: "arrow.triangle.merge")
                            }
                            .accessibilityLabel("Fusionner vers \(entry.name)")
                        }
                    }
                } header: {
                    HStack {
                        Text(group.label)
                        Spacer()
                        Button("Ignorer") { ignoredRaw = (Array(ignored) + [group.key]).joined(separator: "\n") }.font(.caption).textCase(nil)
                    }
                } footer: {
                    Text("L'entrée gardée reprend l'identifiant, l'utilisateur, les notes, le favori et les pièces jointes des autres.")
                }
            }
            if !ignored.isEmpty {
                Button("Réafficher les groupes ignorés (\(ignored.count))") { ignoredRaw = "" }
            }
        }
        .overlay { if loading && groups.isEmpty { ProgressView() } }
        .navigationTitle("Doublons")
        .refreshable { await load() }
        .task { await load() }
    }

    private func path(_ entry: Entry) -> String {
        let names = app.tree.path(of: entry.folderId).map(\.name)
        return (names.isEmpty ? "Racine" : names.joined(separator: " › ")) + " · " + entry.target
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            groups = try await app.client?.duplicates() ?? []
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func merge(keep: Entry, group: DuplicateGroup) async {
        do {
            _ = try await app.client?.merge(keep: keep.id, remove: group.entries.map(\.id).filter { $0 != keep.id })
            await app.refresh()
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Import d'un export Remote Desktop Manager (.rdm) avec aperçu.
struct ImportRDMView: View {
    let app: AppSession
    @State private var file: Data?
    @State private var fileName = ""
    @State private var plan: ImportPlan?
    @State private var folder = "Import RDM"
    @State private var sshDefault = ""
    @State private var rdpDefault = ""
    @State private var picking = false
    @State private var busy = false
    @State private var error: String?
    @State private var result: ImportResult?

    var body: some View {
        Form {
            Section {
                Button(file == nil ? "Choisir un fichier .rdm" : "Changer de fichier (\(fileName))", systemImage: "doc.badge.plus") { picking = true }
            } footer: {
                Text("Dans RDM : Fichier → Exporter → Exporter toutes les entrées, format .rdm, sans mot de passe. Rien n'est créé avant « Importer ».")
            }
            if let plan {
                Section("Aperçu") {
                    LabeledContent("Dossiers", value: "\(plan.folders.count)")
                    LabeledContent("Entrées", value: "\(plan.entries.count)")
                    LabeledContent("Identifiants", value: "\(plan.credentials.count)")
                    LabeledContent("Ignorées", value: "\(plan.skipped.count)")
                    ForEach(plan.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                }
                if !plan.skipped.isEmpty {
                    Section("Non importées") {
                        ForEach(Array(plan.skipped.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading) {
                                Text(item.name)
                                Text("\(item.type) : \(item.reason)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    TextField("Dossier de destination", text: $folder)
                    Picker("Identifiant SSH par défaut", selection: $sshDefault) {
                        Text("Aucun").tag("")
                        ForEach(app.credentials) { Text($0.name).tag($0.id) }
                    }
                    Picker("Identifiant RDP par défaut", selection: $rdpDefault) {
                        Text("Aucun").tag("")
                        ForEach(app.credentials) { Text($0.name).tag($0.id) }
                    }
                } footer: {
                    Text("Les mots de passe chiffrés par RDM ne peuvent pas être relus : ressaisissez-les ensuite dans le coffre.")
                }
                Section {
                    Button("Importer", systemImage: "square.and.arrow.down") { Task { await apply() } }
                        .disabled(busy || folder.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if busy { ProgressView() }
            if let result {
                StatusBanner(message: "Import terminé : \(result.entries) entrée(s), \(result.credentials) identifiant(s), \(result.folders) dossier(s).",
                             symbol: "checkmark.circle.fill", tint: .green)
            }
            if let error { StatusBanner(message: error) }
        }
        .navigationTitle("Importer depuis RDM")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item]) { picked in
            guard case .success(let url) = picked else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                file = try Data(contentsOf: url)
                fileName = url.lastPathComponent
                Task { await preview() }
            } catch {
                self.error = error.localizedDescription
            }
        }
        .task { if app.credentials.isEmpty { await app.loadCredentials() } }
    }

    private func preview() async {
        guard let file, let client = app.client else { return }
        busy = true
        error = nil
        result = nil
        defer { busy = false }
        do { plan = try await client.previewImport(file) } catch { self.error = error.localizedDescription }
    }

    private func apply() async {
        guard let file, let client = app.client else { return }
        busy = true
        defer { busy = false }
        do {
            result = try await client.applyImport(file, folder: folder, sshDefault: sshDefault, rdpDefault: rdpDefault)
            plan = nil
            self.file = nil
            await app.refresh()
            await app.loadCredentials()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Sauvegarde chiffrée : export vers Fichiers, restauration (remplace toutes les données).
struct BackupView: View {
    let app: AppSession
    @State private var password = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var error: String?
    @State private var shared: SharedFile?
    @State private var restoring = false
    @State private var restoreFile: Data?
    @State private var restoreName = ""
    @State private var restorePassword = ""
    @State private var restoreTyped = ""
    @State private var done: String?

    var body: some View {
        Form {
            Section {
                SecureField("Mot de passe de la sauvegarde", text: $password)
                SecureField("Confirmer le mot de passe", text: $confirm)
                Button("Exporter", systemImage: "square.and.arrow.up") { Task { await export() } }
                    .disabled(busy || password.count < 8 || password != confirm)
            } header: {
                Text("Exporter")
            } footer: {
                Text("Archive chiffrée de toutes les données (entrées, coffre, sources, historique). 8 caractères au moins ; sans ce mot de passe, elle est illisible.")
            }
            Section {
                Button(restoreFile == nil ? "Choisir une archive" : "Archive : \(restoreName)", systemImage: "doc.badge.arrow.up") { restoring = true }
                if restoreFile != nil {
                    SecureField("Mot de passe de l'archive", text: $restorePassword)
                    TextField("Tapez RESTAURER pour confirmer", text: $restoreTyped)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Button("Restaurer et remplacer toutes les données", role: .destructive) { Task { await restore() } }
                        .disabled(busy || restorePassword.isEmpty || restoreTyped != "RESTAURER")
                }
            } header: {
                Text("Restaurer")
            } footer: {
                Text("La restauration remplace tout le contenu du serveur Relay, pour tous les appareils.")
            }
            if busy { ProgressView() }
            if let done { StatusBanner(message: done, symbol: "checkmark.circle.fill", tint: .green) }
            if let error { StatusBanner(message: error) }
        }
        .navigationTitle("Sauvegarde")
        .sheet(item: $shared) { file in ShareSheet(url: file.url).presentationDetents([.medium, .large]) }
        .fileImporter(isPresented: $restoring, allowedContentTypes: [.item]) { picked in
            guard case .success(let url) = picked else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            restoreFile = try? Data(contentsOf: url)
            restoreName = url.lastPathComponent
        }
    }

    private func export() async {
        guard let client = app.client else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let data = try await client.exportBackup(password: password)
            let stamp = Date().formatted(.iso8601.year().month().day())
            shared = SharedFile(url: try LocalFiles.save(data, name: "relay-\(stamp).relay"))
            password = ""
            confirm = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func restore() async {
        guard let client = app.client, let restoreFile else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await client.restoreBackup(restoreFile, password: restorePassword)
            done = "Sauvegarde restaurée."
            self.restoreFile = nil
            restorePassword = ""
            restoreTyped = ""
            await app.refresh()
            await app.loadCredentials()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

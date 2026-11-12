import RelayKit
import SwiftUI

extension AppSession {
    /// Dossiers à plat, dans l'ordre de l'arborescence, avec leur profondeur.
    func flattenedFolders(excluding excluded: String? = nil) -> [(folder: Folder, depth: Int)] {
        var out: [(Folder, Int)] = []
        func walk(_ parent: String?, _ depth: Int) {
            for f in tree.folders(in: parent) where f.id != excluded {
                out.append((f, depth))
                walk(f.id, depth + 1)
            }
        }
        walk(nil, 0)
        return out
    }

    /// Identifiant hérité pour un type dans un dossier (en remontant les parents).
    func inheritedCredential(folder: String?, kind: EntryKind) -> Credential? {
        var cursor = tree.folder(folder)
        var hops = 0
        while let f = cursor, hops < 64 {
            if let value = f.credentials[kind.rawValue] {
                return value.flatMap { credential($0) }
            }
            cursor = tree.folder(f.parentId)
            hops += 1
        }
        return nil
    }
}

/// Choix d'un dossier (indenté), racine comprise.
struct FolderPicker: View {
    let app: AppSession
    let title: String
    @Binding var selection: String?
    var excluding: String?

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Racine").tag(String?.none)
            ForEach(app.flattenedFolders(excluding: excluding), id: \.folder.id) { item in
                Text(String(repeating: "   ", count: item.depth) + item.folder.name).tag(Optional(item.folder.id))
            }
        }
    }
}

/// Création ou modification d'une entrée. Les réglages avancés (RDP, SSH…) sont conservés tels quels.
struct EntryEditorView: View {
    let app: AppSession
    let entryId: String?
    @State var input: EntryInput
    @Environment(\.dismiss) private var dismiss
    @State private var loading = false
    @State private var saving = false
    @State private var error: String?
    @State private var preview = false
    @State private var confirmDelete = false

    init(app: AppSession, entryId: String? = nil, input: EntryInput) {
        self.app = app
        self.entryId = entryId
        _input = State(initialValue: input)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom", text: $input.name).accessibilityIdentifier("editorName")
                    if entryId == nil {
                        Picker("Type", selection: $input.kind) {
                            ForEach(EntryKind.creatable, id: \.self) { Text($0.title).tag($0) }
                        }
                        .onChange(of: input.kind) { _, kind in input.port = EntryInput.defaultPort(kind) }
                    } else {
                        LabeledContent("Type", value: input.kind.title)
                    }
                    FolderPicker(app: app, title: "Dossier", selection: $input.folderId)
                }
                if input.kind == .web {
                    Section("Adresse") {
                        TextField("https://…", text: $input.url).keyboardType(.URL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                } else if input.kind != .pve {
                    Section("Adresse") {
                        TextField("Hôte ou adresse IP", text: $input.host).keyboardType(.URL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("editorHost")
                        TextField("Port", value: $input.port, format: .number.grouping(.never)).keyboardType(.numberPad)
                    }
                }
                if input.kind != .pve {
                    Section {
                        TextField("Utilisateur (facultatif)", text: $input.username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Picker("Identifiant", selection: $input.credentialId) {
                            Text(inheritedLabel).tag(String?.none)
                            ForEach(app.credentials) { c in Text(c.name).tag(Optional(c.id)) }
                        }
                    } header: {
                        Text("Authentification")
                    } footer: {
                        Text("Sans identifiant choisi, l'entrée utilise celui défini sur son dossier pour ce type.")
                    }
                }
                Section {
                    if preview {
                        Text(markdown(input.notes)).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextEditor(text: $input.notes).frame(minHeight: 120).font(.callout)
                    }
                    Toggle("Aperçu", isOn: $preview)
                } header: {
                    Text("Notes (Markdown)")
                }
                Section {
                    Toggle("Favori", isOn: $input.favorite)
                } footer: {
                    if !input.settings.isEmpty {
                        Text("Réglages avancés conservés : \(input.settings.keys.sorted().joined(separator: ", ")). Ils se modifient dans Relay web.")
                    }
                }
                if let error { StatusBanner(message: error) }
                if entryId != nil {
                    Section {
                        Button("Supprimer l'entrée", role: .destructive) { confirmDelete = true }
                            .accessibilityIdentifier("editorDelete")
                    }
                }
            }
            .disabled(loading)
            .overlay { if loading { ProgressView() } }
            .navigationTitle(entryId == nil ? "Nouvelle entrée" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { Task { await save() } }
                        .disabled(saving || !valid)
                        .accessibilityIdentifier("editorSave")
                }
            }
            .confirmationDialog("Supprimer « \(input.name) » ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) { Task { await delete() } }
            } message: {
                Text(input.kind == .pve ? "Une synchronisation Proxmox ne la recréera pas." : "Ses pièces jointes sont aussi supprimées.")
            }
            .task { await loadFullEntry() }
        }
    }

    private var inheritedLabel: String {
        if let c = app.inheritedCredential(folder: input.folderId, kind: input.kind) { return "Hérité du dossier : \(c.name)" }
        return "Aucun"
    }

    private var valid: Bool {
        let name = !input.name.trimmingCharacters(in: .whitespaces).isEmpty
        switch input.kind {
        case .web: return name && URL(string: input.url)?.scheme != nil
        case .pve, .other: return name
        default: return name && !input.host.trimmingCharacters(in: .whitespaces).isEmpty && (1...65535).contains(input.port)
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    /// Relit la fiche complète (réglages avancés) avant modification.
    private func loadFullEntry() async {
        if app.credentials.isEmpty { await app.loadCredentials() }
        guard let entryId, let client = app.client else { return }
        loading = true
        defer { loading = false }
        do { input = try await client.entryInput(entryId) } catch { self.error = error.localizedDescription }
    }

    private func save() async {
        guard let client = app.client else { return }
        saving = true
        defer { saving = false }
        do {
            input.name = input.name.trimmingCharacters(in: .whitespaces)
            input.host = input.host.trimmingCharacters(in: .whitespaces)
            _ = try await client.saveEntry(input, id: entryId)
            await app.refresh()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete() async {
        guard let entryId, let client = app.client else { return }
        do {
            try await client.deleteEntry(entryId)
            await app.refresh()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Création ou modification d'un dossier, avec ses identifiants hérités par type.
struct FolderEditorView: View {
    let app: AppSession
    let folder: Folder?
    @State private var name: String
    @State private var parentId: String?
    @State private var inherited: [String: String?]
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var saving = false
    @State private var confirmDelete = false

    private static let kinds: [EntryKind] = [.ssh, .rdp, .vnc, .web]

    init(app: AppSession, folder: Folder?, parentId: String?) {
        self.app = app
        self.folder = folder
        _name = State(initialValue: folder?.name ?? "")
        _parentId = State(initialValue: folder?.parentId ?? parentId)
        _inherited = State(initialValue: folder?.credentials ?? [:])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom du dossier", text: $name).accessibilityIdentifier("folderName")
                    FolderPicker(app: app, title: "Dans", selection: $parentId, excluding: folder?.id)
                }
                if folder != nil {
                    Section {
                        ForEach(Self.kinds, id: \.self) { kind in
                            Picker(kind.title, selection: binding(for: kind)) {
                                Text("Hériter du parent").tag(Choice.inherit)
                                Text("Aucun").tag(Choice.none)
                                ForEach(app.credentials) { c in Text(c.name).tag(Choice.credential(c.id)) }
                            }
                        }
                    } header: {
                        Text("Identifiants par défaut")
                    } footer: {
                        Text("Utilisés par les entrées du dossier (et des sous-dossiers) qui n'ont pas d'identifiant propre.")
                    }
                }
                if let error { StatusBanner(message: error) }
                if folder != nil {
                    Section {
                        Button("Supprimer le dossier", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(folder == nil ? "Nouveau dossier" : "Modifier le dossier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { Task { await save() } }
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("folderSave")
                }
            }
            .confirmationDialog("Supprimer « \(name) » ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) { Task { await delete() } }
            } message: {
                Text("Le dossier doit être vide, sinon Relay refuse la suppression.")
            }
            .task { if app.credentials.isEmpty { await app.loadCredentials() } }
        }
    }

    enum Choice: Hashable {
        case inherit, none
        case credential(String)
    }

    private func binding(for kind: EntryKind) -> Binding<Choice> {
        Binding {
            guard let value = inherited[kind.rawValue] else { return .inherit }
            return value.map(Choice.credential) ?? .none
        } set: { choice in
            switch choice {
            case .inherit: inherited.removeValue(forKey: kind.rawValue)
            case .none: inherited[kind.rawValue] = .some(nil)
            case .credential(let id): inherited[kind.rawValue] = .some(id)
            }
        }
    }

    private func save() async {
        guard let client = app.client else { return }
        saving = true
        defer { saving = false }
        do {
            let saved = try await client.saveFolder(name: name.trimmingCharacters(in: .whitespaces), parentId: parentId, id: folder?.id)
            if folder != nil { try await client.setFolderCredentials(saved.id, inherited) }
            await app.refresh()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete() async {
        guard let folder, let client = app.client else { return }
        do {
            try await client.deleteFolder(folder.id)
            await app.refresh()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

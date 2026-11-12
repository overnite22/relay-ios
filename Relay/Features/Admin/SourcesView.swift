import RelayKit
import SwiftUI

/// Sources de synchronisation Proxmox et NetBox.
struct SourcesView: View {
    let app: AppSession
    @State private var sources: [SyncSource] = []
    @State private var error: String?
    @State private var editing: EditingBox<SyncSource?>?
    @State private var newKind: String?

    var body: some View {
        List {
            if let error { StatusBanner(message: error) }
            if sources.isEmpty && error == nil {
                ContentUnavailableView("Aucune source", systemImage: "arrow.triangle.2.circlepath",
                                       description: Text("Ajoutez Proxmox VE ou NetBox pour créer les entrées automatiquement."))
            }
            ForEach(sources) { source in
                NavigationLink {
                    SourceDetailView(app: app, source: source) { await load() }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.name)
                        Text("\(source.kindTitle) · \(source.intervalMin == 0 ? "manuelle" : "toutes les \(source.intervalMin) min")")
                            .font(.caption).foregroundStyle(.secondary)
                        if !source.lastStatus.isEmpty {
                            Text(source.lastStatus).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                .accessibilityIdentifier("source-\(source.name)")
            }
        }
        .navigationTitle("Sources de synchro")
        .toolbar {
            Menu {
                Button("Proxmox VE") { editing = EditingBox(value: nil); newKind = "proxmox" }
                Button("NetBox") { editing = EditingBox(value: nil); newKind = "netbox" }
            } label: {
                Label("Ajouter", systemImage: "plus")
            }
        }
        .sheet(item: $editing) { box in
            SourceEditorView(app: app, source: box.value, kind: box.value?.kind ?? newKind ?? "proxmox") { await load() }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            sources = try await app.client?.sources() ?? []
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct SourceDetailView: View {
    let app: AppSession
    @State var source: SyncSource
    let onChange: () async -> Void
    @State private var busy: String?
    @State private var message: (ok: Bool, text: String)?
    @State private var editing = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                LabeledContent("Type", value: source.kindTitle)
                LabeledContent("Adresse", value: source.url)
                if !source.tokenId.isEmpty { LabeledContent("Jeton", value: source.tokenId) }
                LabeledContent("Vérification TLS", value: source.verifyTls ? "Oui" : "Non")
                LabeledContent("Synchronisation", value: source.intervalMin == 0 ? "Manuelle" : "Toutes les \(source.intervalMin) min")
                if let at = source.lastSyncAt { LabeledContent("Dernière", value: at.shortDate) }
                if !source.lastStatus.isEmpty { Text(source.lastStatus).font(.caption).foregroundStyle(.secondary) }
            }
            Section {
                action("Tester la connexion", "checkmark.shield", key: "test") { try await app.client?.testSource(source.id) }
                action("Synchroniser maintenant", "arrow.triangle.2.circlepath", key: "sync") {
                    let result = try await app.client?.syncSource(source.id)
                    await app.refresh()
                    return result
                }
                .accessibilityIdentifier("sourceSync")
                Button("Réautoriser les entrées supprimées", systemImage: "arrow.uturn.backward") {
                    Task {
                        busy = "clear"
                        defer { busy = nil }
                        do {
                            let text = try await app.client?.clearExclusions(source.id) ?? ""
                            message = (true, text)
                        } catch {
                            message = (false, error.localizedDescription)
                        }
                    }
                }
                .disabled(busy != nil)
            } footer: {
                Text("Les entrées supprimées ou fusionnées ne sont pas recréées par la synchronisation, sauf réautorisation.")
            }
            if let message {
                StatusBanner(message: message.text, symbol: message.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                             tint: message.ok ? .green : .orange)
            }
            Section {
                Button("Supprimer la source", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Les entrées déjà créées restent dans l'arborescence.")
            }
        }
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Modifier", systemImage: "pencil") { editing = true } }
        .sheet(isPresented: $editing) {
            SourceEditorView(app: app, source: source, kind: source.kind) {
                if let updated = try? await app.client?.sources().first(where: { $0.id == source.id }) { source = updated }
                await onChange()
            }
        }
        .confirmationDialog("Supprimer « \(source.name) » ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                Task {
                    try? await app.client?.deleteSource(source.id)
                    await onChange()
                    dismiss()
                }
            }
        }
    }

    private func action(_ title: String, _ symbol: String, key: String, run: @escaping () async throws -> SourceResult?) -> some View {
        Button {
            Task {
                busy = key
                defer { busy = nil }
                do {
                    if let result = try await run() { message = (result.ok, result.message) }
                    await onChange()
                } catch {
                    message = (false, error.localizedDescription)
                }
            }
        } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                if busy == key { ProgressView() }
            }
        }
        .disabled(busy != nil)
    }
}

struct SourceEditorView: View {
    let app: AppSession
    let source: SyncSource?
    let kind: String
    let onSave: () async -> Void
    @State private var input: SyncSourceInput
    @State private var secret = ""
    @State private var error: String?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    init(app: AppSession, source: SyncSource?, kind: String, onSave: @escaping () async -> Void) {
        self.app = app
        self.source = source
        self.kind = kind
        self.onSave = onSave
        _input = State(initialValue: source.map(SyncSourceInput.init) ?? SyncSourceInput(kind: kind, verifyTls: true, intervalMin: 0))
    }

    private var isProxmox: Bool { kind == "proxmox" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom", text: $input.name)
                    TextField(isProxmox ? "https://pve.example.com:8006" : "https://netbox.example.com", text: $input.url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("Vérifier le certificat TLS", isOn: $input.verifyTls)
                }
                Section {
                    if isProxmox {
                        TextField("utilisateur@pve!jeton", text: $input.tokenId).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    SecureField(source?.hasSecret == true ? "Secret inchangé" : (isProxmox ? "Secret du jeton" : "Jeton d'API"), text: $secret)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: {
                    Text("Accès")
                } footer: {
                    Text(isProxmox ? "Jeton en lecture seule (Sys.Audit, VM.Audit, VM.Console)." : "Jeton NetBox en lecture seule.")
                }
                Section("Contenu") {
                    if isProxmox {
                        optionToggle("Entrées SSH et web des nœuds", "nodeEntries", default: true)
                        optionToggle("Entrées SSH/RDP des invités", "guestEntries", default: true)
                    } else {
                        optionToggle("Équipements", "devices", default: true)
                        optionToggle("Machines virtuelles", "vms", default: true)
                    }
                    credentialOption("Identifiant SSH par défaut", "sshCredentialId")
                    credentialOption("Identifiant RDP par défaut", "rdpCredentialId")
                }
                Section {
                    Picker("Synchronisation", selection: $input.intervalMin) {
                        Text("Manuelle").tag(0)
                        ForEach([15, 30, 60, 360, 1440], id: \.self) { Text($0 < 60 ? "Toutes les \($0) min" : "Toutes les \($0 / 60) h").tag($0) }
                    }
                }
                if let error { StatusBanner(message: error) }
            }
            .navigationTitle(source == nil ? (isProxmox ? "Nouvelle source Proxmox" : "Nouvelle source NetBox") : "Modifier la source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { Task { await save() } }
                        .disabled(saving || input.name.isEmpty || input.url.isEmpty || (source == nil && secret.isEmpty))
                }
            }
            .task { if app.credentials.isEmpty { await app.loadCredentials() } }
        }
    }

    private func optionToggle(_ title: String, _ key: String, default value: Bool) -> some View {
        Toggle(title, isOn: Binding(
            get: { if case .bool(let b)? = input.options[key] { return b }; return value },
            set: { input.options[key] = .bool($0) }
        ))
    }

    private func credentialOption(_ title: String, _ key: String) -> some View {
        Picker(title, selection: Binding<String>(
            get: { if case .string(let s)? = input.options[key] { return s }; return "" },
            set: { input.options[key] = $0.isEmpty ? nil : .string($0) }
        )) {
            Text("Aucun").tag("")
            ForEach(app.credentials) { Text($0.name).tag($0.id) }
        }
    }

    private func save() async {
        guard let client = app.client else { return }
        saving = true
        defer { saving = false }
        var payload = input
        payload.kind = kind
        payload.secret = secret.isEmpty ? nil : secret
        do {
            _ = try await client.saveSource(payload, id: source?.id)
            await onSave()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

import RelayKit
import SwiftUI

/// Création ou modification d'un identifiant. Secrets laissés vides = inchangés (sauf effacement demandé).
struct CredentialEditorView: View {
    let app: AppSession
    let credential: Credential?
    @State private var input: CredentialInput
    @State private var password = ""
    @State private var privateKey = ""
    @State private var passphrase = ""
    @State private var totp = ""
    @State private var clear: Set<String> = []
    @State private var importingKey = false
    @State private var error: String?
    @State private var saving = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    init(app: AppSession, credential: Credential?) {
        self.app = app
        self.credential = credential
        _input = State(initialValue: CredentialInput(name: credential?.name ?? "", username: credential?.username ?? "",
                                                      domain: credential?.domain ?? "", notes: credential?.notes ?? ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom", text: $input.name).accessibilityIdentifier("credName")
                    TextField("Utilisateur", text: $input.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .textContentType(.username)
                    TextField("Domaine (facultatif)", text: $input.domain).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                secretSection("Mot de passe", key: "password", exists: credential?.hasPassword ?? false) {
                    SecureField(placeholder(credential?.hasPassword), text: $password).textContentType(.password)
                        .accessibilityIdentifier("credPassword")
                }
                secretSection("Clé privée SSH", key: "privateKey", exists: credential?.hasPrivateKey ?? false) {
                    TextEditor(text: $privateKey).font(.caption.monospaced()).frame(minHeight: 80)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Importer depuis Fichiers", systemImage: "doc.badge.plus") { importingKey = true }
                }
                secretSection("Phrase secrète de la clé", key: "passphrase", exists: credential?.hasPassphrase ?? false) {
                    SecureField(placeholder(credential?.hasPassphrase), text: $passphrase)
                }
                secretSection("Secret TOTP", key: "totp", exists: credential?.hasTotp ?? false) {
                    SecureField(credential?.hasTotp == true ? "Inchangé" : "Base32 ou otpauth://…", text: $totp)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Notes") {
                    TextEditor(text: $input.notes).frame(minHeight: 60)
                }
                if let error { StatusBanner(message: error) }
                if credential != nil {
                    Section {
                        Button("Supprimer l'identifiant", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Les entrées qui l'utilisent n'auront plus d'identifiant.")
                    }
                }
            }
            .navigationTitle(credential == nil ? "Nouvel identifiant" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { Task { await save() } }
                        .disabled(saving || input.name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("credSave")
                }
            }
            .fileImporter(isPresented: $importingKey, allowedContentTypes: [.item]) { result in
                guard case .success(let url) = result else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), data.count < 64 << 10, let text = String(data: data, encoding: .utf8) {
                    privateKey = text
                } else {
                    error = "Ce fichier n'est pas une clé privée lisible."
                }
            }
            .confirmationDialog("Supprimer « \(input.name) » ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) { Task { await delete() } }
            }
        }
    }

    private func placeholder(_ exists: Bool?) -> String { exists == true ? "Inchangé" : "" }

    @ViewBuilder
    private func secretSection<Content: View>(_ title: String, key: String, exists: Bool, @ViewBuilder content: () -> Content) -> some View {
        Section {
            if !clear.contains(key) { content() }
            if exists {
                Toggle("Effacer la valeur enregistrée", isOn: Binding(
                    get: { clear.contains(key) },
                    set: { if $0 { clear.insert(key) } else { clear.remove(key) } }
                ))
            }
        } header: {
            Text(title)
        }
    }

    /// nil = inchangé ; "" = effacé ; sinon nouvelle valeur.
    private func value(_ key: String, _ text: String) -> String? {
        if clear.contains(key) { return "" }
        return text.isEmpty ? nil : text
    }

    private func save() async {
        guard let client = app.client else { return }
        saving = true
        defer { saving = false }
        var payload = input
        payload.password = value("password", password)
        payload.privateKey = value("privateKey", privateKey.trimmingCharacters(in: .whitespacesAndNewlines))
        payload.passphrase = value("passphrase", passphrase)
        payload.totp = value("totp", totp.trimmingCharacters(in: .whitespaces))
        do {
            _ = try await client.saveCredential(payload, id: credential?.id)
            await app.loadCredentials()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete() async {
        guard let credential, let client = app.client else { return }
        do {
            try await client.deleteCredential(credential.id)
            await app.loadCredentials()
            await app.refresh()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

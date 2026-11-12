import RelayKit
import SwiftUI

/// Coffre : identifiants partagés par les entrées.
struct VaultView: View {
    let app: AppSession
    @State private var query = ""
    @State private var creating = false

    var body: some View {
        List {
            let list = filtered
            if list.isEmpty && !app.loading {
                ContentUnavailableView(query.isEmpty ? "Coffre vide" : "Aucun résultat", systemImage: "key",
                                       description: Text(query.isEmpty ? "Ajoutez des identifiants dans Relay web." : ""))
            }
            ForEach(list) { credential in
                NavigationLink(value: Route.credential(credential.id)) {
                    HStack(spacing: 12) {
                        Image(systemName: credential.hasPrivateKey ? "key.horizontal.fill" : "person.badge.key.fill")
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.relayAccent.gradient, in: RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(credential.name)
                            Text(credential.account.isEmpty ? "Sans utilisateur" : credential.account)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if credential.hasTotp {
                            Image(systemName: "clock.badge.checkmark").foregroundStyle(.secondary).accessibilityLabel("Code TOTP")
                        }
                    }
                }
                .accessibilityIdentifier("credential-\(credential.name)")
            }
        }
        .navigationTitle("Coffre")
        .toolbar {
            Button("Nouvel identifiant", systemImage: "plus") { creating = true }.accessibilityIdentifier("credNew")
        }
        .sheet(isPresented: $creating) { CredentialEditorView(app: app, credential: nil) }
        .searchable(text: $query, prompt: "Nom ou utilisateur")
        .refreshable { await app.loadCredentials() }
        .task { await app.loadCredentials() }
    }

    private var filtered: [Credential] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return app.credentials }
        return app.credentials.filter { "\($0.name) \($0.account) \($0.notes)".lowercased().contains(q) }
    }
}

/// Détail d'un identifiant : copie de l'utilisateur et des secrets (après Face ID), code TOTP.
struct CredentialDetailView: View {
    let app: AppSession
    let credentialId: String
    @State private var revealed: String?
    @State private var totp: TOTPCode?
    @State private var totpFetched = Date()
    @State private var error: String?
    @State private var editing = false

    var body: some View {
        if let credential = app.credential(credentialId) {
            content(credential)
        } else {
            ProgressView().task { await app.loadCredentials() }
        }
    }

    private func content(_ c: Credential) -> some View {
        List {
            Section {
                if !c.username.isEmpty {
                    LabeledContent("Utilisateur") {
                        HStack(spacing: 10) {
                            Text(c.account).textSelection(.enabled)
                            CopyButton(label: "l'utilisateur") { c.account }
                        }
                    }
                }
                if c.hasPassword {
                    LabeledContent("Mot de passe") {
                        HStack(spacing: 10) {
                            Text(revealed ?? "••••••••").font(.body.monospaced()).textSelection(.enabled)
                                .accessibilityIdentifier("credentialPassword")
                            Button(revealed == nil ? "Afficher" : "Masquer", systemImage: revealed == nil ? "eye" : "eye.slash") {
                                Task { await toggleReveal(c) }
                            }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                            .accessibilityIdentifier("credentialReveal")
                            CopyButton(label: "le mot de passe") { await secret(c, .password) }
                        }
                    }
                }
                if c.hasPrivateKey {
                    LabeledContent("Clé privée SSH") {
                        CopyButton(label: "la clé privée") { await secret(c, .privateKey) }
                    }
                }
                if c.hasPassphrase {
                    LabeledContent("Phrase secrète") {
                        CopyButton(label: "la phrase secrète") { await secret(c, .passphrase) }
                    }
                }
            } footer: {
                Text("Les secrets copiés expirent du presse-papiers après 90 secondes et ne sont pas partagés avec vos autres appareils.")
            }

            if c.hasTotp {
                Section("Code à usage unique") {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        totpRow(c, now: context.date)
                    }
                }
            }

            if !c.notes.isEmpty {
                Section("Notes") { Text(c.notes).font(.callout).textSelection(.enabled) }
            }
            if let error { StatusBanner(message: error) }
        }
        .navigationTitle(c.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Modifier", systemImage: "pencil") { editing = true }.accessibilityIdentifier("credEdit") }
        .sheet(isPresented: $editing) { CredentialEditorView(app: app, credential: c) }
        .onDisappear { revealed = nil }
    }

    @ViewBuilder private func totpRow(_ c: Credential, now: Date) -> some View {
        if let totp {
            let elapsed = Int(now.timeIntervalSince(totpFetched))
            let remaining = max(0, totp.remaining - elapsed)
            HStack {
                Text(spaced(totp.code)).font(.system(.title, design: .monospaced).weight(.semibold))
                    .foregroundStyle(remaining <= 5 ? .orange : .primary)
                    .accessibilityIdentifier("credentialTotp")
                Spacer()
                Gauge(value: Double(remaining), in: 0...Double(max(totp.period, 1))) { EmptyView() }
                    .gaugeStyle(.accessoryCircularCapacity).scaleEffect(0.6).frame(width: 36, height: 36)
                    .accessibilityLabel("\(remaining) secondes restantes")
                CopyButton(label: "le code") { totp.code }
            }
            .task(id: remaining == 0) {
                if remaining == 0 { await loadTotp(c) }
            }
        } else {
            Button("Afficher le code", systemImage: "clock.badge.checkmark") { Task { await loadTotp(c) } }
                .accessibilityIdentifier("credentialShowTotp")
        }
    }

    private func spaced(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }

    private func secret(_ c: Credential, _ field: SecretField) async -> String? {
        error = nil
        guard await Biometrics.unlock(app), let client = app.client else { return nil }
        do { return try await client.reveal(c.id, field: field) } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    private func toggleReveal(_ c: Credential) async {
        if revealed != nil {
            revealed = nil
            return
        }
        revealed = await secret(c, .password)
    }

    private func loadTotp(_ c: Credential) async {
        guard await Biometrics.unlock(app), let client = app.client else { return }
        do {
            totp = try await client.totp(c.id)
            totpFetched = Date()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

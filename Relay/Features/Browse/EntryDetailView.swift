import RelayKit
import SwiftUI

/// Fiche d'une entrée : ouverture, disponibilité, informations, identifiant et notes.
struct EntryDetailView: View {
    let app: AppSession
    let entryId: String
    @Environment(\.openURL) private var openURL
    @State private var testing = false
    @State private var lastTest: ConnectionTest?
    @State private var testError: String?
    @State private var editing = false

    var body: some View {
        if let entry = app.tree.entry(entryId) {
            content(entry)
        } else {
            ContentUnavailableView("Entrée introuvable", systemImage: "questionmark.folder",
                                   description: Text("Elle a peut-être été supprimée dans Relay web."))
        }
    }

    private func content(_ entry: Entry) -> some View {
        List {
            Section {
                HStack(spacing: 14) {
                    KindBadge(kind: entry.kind, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.name).font(.title3.bold())
                        Text(pathText(entry)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                primaryAction(entry)
            }

            if entry.kind.isMonitored {
                Section("Disponibilité") {
                    let test = lastTest ?? app.status[entry.id]
                    HStack {
                        StatusDot(test: test)
                        VStack(alignment: .leading) {
                            Text(test?.statusTitle ?? "Pas encore mesurée")
                            if let test {
                                Text("\(test.address) · \(Int(test.durationMs)) ms · \(test.checkedAt.relativeDate)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            Task { await runTest(entry) }
                        } label: {
                            if testing { ProgressView() } else { Text("Tester") }
                        }
                        .buttonStyle(.bordered)
                        .disabled(testing)
                        .accessibilityIdentifier("entryTest")
                    }
                    if let testError { StatusBanner(message: testError) }
                }
            }

            Section("Connexion") {
                if entry.kind == .web {
                    info("URL", entry.url, copy: true)
                } else {
                    info("Hôte", entry.host, copy: true)
                    if entry.port > 0 { info("Port", String(entry.port)) }
                }
                if !entry.username.isEmpty { info("Utilisateur", entry.username, copy: true) }
                if let credential = app.credential(entry.credentialId) {
                    NavigationLink(value: Route.credential(credential.id)) {
                        LabeledContent("Identifiant") {
                            Label(credential.name, systemImage: "key.fill").labelStyle(.titleAndIcon)
                        }
                    }
                } else if entry.credentialId != nil {
                    LabeledContent("Identifiant", value: "Coffre")
                }
                if entry.sourceId != nil {
                    LabeledContent("Origine", value: "Synchronisation")
                }
            }

            if !entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Notes") {
                    Text(markdown(entry.notes)).textSelection(.enabled).font(.callout)
                }
            }
            AttachmentsSection(app: app, entryId: entry.id)
        }
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) {
            EntryEditorView(app: app, entryId: entry.id, input: EntryInput(folderId: entry.folderId, name: entry.name, kind: entry.kind))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Modifier", systemImage: "pencil") { editing = true }.accessibilityIdentifier("entryEdit")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(entry.favorite ? "Retirer des favoris" : "Ajouter aux favoris",
                       systemImage: entry.favorite ? "star.fill" : "star") {
                    Task { await app.toggleFavorite(entry) }
                }
                .tint(.yellow)
                .accessibilityIdentifier("entryFavorite")
            }
        }
        .task { if app.credentials.isEmpty { await app.loadCredentials() } }
    }

    @ViewBuilder private func primaryAction(_ entry: Entry) -> some View {
        switch entry.kind {
        case .ssh, .rdp, .vnc, .pve:
            Button {
                app.open(.entry(entry, record: false))
            } label: {
                Label(entry.kind == .pve ? "Ouvrir la console" : "Ouvrir la session \(entry.kind.title)", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("entryOpen")
            Button("Ouvrir et enregistrer", systemImage: "record.circle") { app.open(.entry(entry, record: true)) }
                .accessibilityIdentifier("entryOpenRecord")
        case .web:
            if let url = URL(string: entry.url), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                Button {
                    openURL(url)
                } label: {
                    Label("Ouvrir dans Safari", systemImage: "safari").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        case .other:
            StatusBanner(message: "Ce type d'entrée n'est pas encore pris en charge par l'app.", symbol: "info.circle.fill", tint: .blue)
        }
    }

    private func info(_ label: String, _ value: String, copy: Bool = false) -> some View {
        LabeledContent(label) {
            HStack(spacing: 10) {
                Text(value).textSelection(.enabled).lineLimit(2).multilineTextAlignment(.trailing)
                if copy { CopyButton(label: label) { value } }
            }
        }
    }

    private func pathText(_ entry: Entry) -> String {
        let names = app.tree.path(of: entry.folderId).map(\.name)
        let base = names.isEmpty ? "Racine" : names.joined(separator: " › ")
        return "\(entry.kind.title) · \(base)"
    }

    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private func runTest(_ entry: Entry) async {
        guard let client = app.client else { return }
        testing = true
        testError = nil
        defer { testing = false }
        do {
            lastTest = try await client.testConnection(entry.id)
            await app.refreshStatus()
        } catch {
            testError = error.localizedDescription
        }
    }
}

import RelayKit
import SwiftUI

/// Journal d'activité du serveur Relay.
struct AuditView: View {
    let app: AppSession
    @State private var events: [AuditEvent] = []
    @State private var query = ""
    @State private var error: String?
    @State private var loading = false

    static let labels: [String: String] = [
        "session.open": "Ouverture de session", "session.close": "Fin de session",
        "entry.create": "Entrée créée", "entry.update": "Entrée modifiée", "entry.delete": "Entrée supprimée",
        "folder.create": "Dossier créé", "folder.update": "Dossier modifié", "folder.delete": "Dossier supprimé",
        "credential.create": "Identifiant créé", "credential.update": "Identifiant modifié", "credential.delete": "Identifiant supprimé",
        "credential.reveal": "Secret affiché / copié", "credential.totp": "Code TOTP affiché",
        "source.create": "Source ajoutée", "source.update": "Source modifiée", "source.delete": "Source supprimée",
        "source.sync": "Synchronisation", "import.rdm": "Import RDM",
        "device.create": "Appareil appairé", "device.delete": "Appareil révoqué",
    ]

    var body: some View {
        List {
            if let error { StatusBanner(message: error) }
            ForEach(filtered) { e in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(Self.labels[e.action] ?? e.action).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(e.at.shortDate).font(.caption2).foregroundStyle(.secondary)
                    }
                    if !e.target.isEmpty { Text(e.target).font(.callout).lineLimit(2) }
                    Text([e.user, e.detail].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .padding(.vertical, 2)
            }
        }
        .overlay { if loading && events.isEmpty { ProgressView() } }
        .navigationTitle("Journal d'activité")
        .searchable(text: $query, prompt: "Filtrer")
        .refreshable { await load() }
        .task { await load() }
    }

    private var filtered: [AuditEvent] {
        let q = query.lowercased()
        guard !q.isEmpty else { return events }
        return events.filter { e in
            [e.user, e.action, Self.labels[e.action] ?? "", e.target, e.detail].contains { $0.lowercased().contains(q) }
        }
    }

    private func load() async {
        guard let client = app.client else { return }
        loading = true
        defer { loading = false }
        do {
            events = try await client.audit(limit: 300)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

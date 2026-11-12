import RelayKit
import SwiftUI

struct EntryRow: View {
    let entry: Entry
    let status: ConnectionTest?
    var path: String?

    var body: some View {
        HStack(spacing: 12) {
            KindBadge(kind: entry.kind)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.name).font(.body).lineLimit(1)
                    if entry.favorite {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow).accessibilityLabel("Favori")
                    }
                }
                Text(path ?? subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if entry.kind.isMonitored { StatusDot(test: status) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("entry-\(entry.name)")
    }

    private var subtitle: String {
        let target = entry.target
        return target.isEmpty ? entry.kind.title : "\(entry.kind.title) · \(target)"
    }
}

/// Actions communes d'une entrée (glisser et menu contextuel).
struct EntryActions: ViewModifier {
    let entry: Entry
    let app: AppSession

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading) {
                if entry.kind.opensNatively {
                    Button("Ouvrir", systemImage: "play.fill") { app.open(.entry(entry, record: false)) }.tint(.relayAccent)
                }
            }
            .swipeActions(edge: .trailing) {
                Button(entry.favorite ? "Retirer" : "Favori", systemImage: entry.favorite ? "star.slash" : "star") {
                    Task { await app.toggleFavorite(entry) }
                }
                .tint(.yellow)
            }
            .contextMenu {
                if entry.kind.opensNatively {
                    Button("Ouvrir", systemImage: "play.fill") { app.open(.entry(entry, record: false)) }
                    Button("Ouvrir et enregistrer", systemImage: "record.circle") { app.open(.entry(entry, record: true)) }
                }
                if !entry.host.isEmpty {
                    Button("Copier l'hôte", systemImage: "doc.on.doc") { UIPasteboard.general.string = entry.host }
                }
                Button(entry.favorite ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: "star") {
                    Task { await app.toggleFavorite(entry) }
                }
            }
    }
}

extension View {
    func entryActions(_ entry: Entry, app: AppSession) -> some View { modifier(EntryActions(entry: entry, app: app)) }
}

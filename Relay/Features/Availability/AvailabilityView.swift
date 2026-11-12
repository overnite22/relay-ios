import RelayKit
import SwiftUI

/// Disponibilité : entrées dont le port ne répond pas, puis celles qui répondent.
struct AvailabilityView: View {
    let app: AppSession
    @State private var filter: Filter = .down
    @State private var folderFilter: String?
    @State private var retest: (done: Int, total: Int)?

    enum Filter: String, CaseIterable, Identifiable {
        case down, up, unknown
        var id: String { rawValue }
        var title: String {
            switch self {
            case .down: return "Injoignables"
            case .up: return "Accessibles"
            case .unknown: return "Sans mesure"
            }
        }
    }

    var body: some View {
        let monitored = app.tree.entries.filter { $0.kind.isMonitored && inFolder($0) }
        let down = monitored.filter { app.status[$0.id].map { !$0.reachable } ?? false }
        let up = monitored.filter { app.status[$0.id]?.reachable ?? false }
        let unknown = monitored.filter { app.status[$0.id] == nil }
        let shown = Self.sorted(filter == .down ? down : (filter == .up ? up : unknown))

        List {
            Section {
                HStack(spacing: 0) {
                    counter(up.count, "Accessibles", .green)
                    counter(down.count, "Injoignables", .red)
                    counter(unknown.count, "Sans mesure", .gray)
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8))
                Picker("Filtre", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("availabilityFilter")
                FolderPicker(app: app, title: "Dossier", selection: $folderFilter)
                Button {
                    Task { await app.retest(monitored) { done, total in retest = (done, total) }; retest = nil }
                } label: {
                    HStack {
                        Label(folderFilter == nil ? "Retester tout" : "Retester ce dossier", systemImage: "arrow.clockwise")
                        Spacer()
                        if let retest { Text("\(retest.done)/\(retest.total)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    }
                }
                .disabled(retest != nil || monitored.isEmpty)
                .accessibilityIdentifier("availabilityRetest")
            } footer: {
                Text("Relay teste le port de chaque entrée SSH, RDP et VNC toutes les minutes, depuis le serveur.")
            }
            Section {
                if shown.isEmpty {
                    Text(filter == .down ? "Tout répond." : "Aucune entrée.").foregroundStyle(.secondary)
                }
                ForEach(shown) { entry in
                    NavigationLink(value: Route.entry(entry.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            EntryRow(entry: entry, status: app.status[entry.id])
                            if let test = app.status[entry.id], !test.reachable {
                                Text("\(test.statusTitle) · \(test.checkedAt.relativeDate)")
                                    .font(.caption2).foregroundStyle(.red).padding(.leading, 42)
                            }
                        }
                    }
                    .entryActions(entry, app: app)
                }
            }
        }
        .navigationTitle("Disponibilité")
        .refreshable { await app.refreshStatus() }
        .task {
            while !Task.isCancelled {
                await app.refreshStatus()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private static func sorted(_ entries: [Entry]) -> [Entry] {
        entries.sorted { (a: Entry, b: Entry) -> Bool in a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending }
    }

    /// Vrai si l'entrée est dans le dossier filtré (sous-dossiers compris).
    private func inFolder(_ entry: Entry) -> Bool {
        guard let folderFilter else { return true }
        return app.tree.path(of: entry.folderId).contains { $0.id == folderFilter }
    }

    private func counter(_ n: Int, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.title2.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

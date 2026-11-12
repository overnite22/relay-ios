import RelayKit
import SwiftUI

/// Disponibilité : entrées dont le port ne répond pas, puis celles qui répondent.
struct AvailabilityView: View {
    let app: AppSession
    @State private var filter: Filter = .down

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
        let monitored = app.tree.entries.filter(\.kind.opensNatively)
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

    private func counter(_ n: Int, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.title2.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

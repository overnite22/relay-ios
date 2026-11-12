import RelayKit
import SwiftUI

/// Interface principale : onglets Connexions, Disponibilité, Coffre et Plus.
struct HomeView: View {
    @Bindable var app: AppSession
    @State private var tab = Tab.connections
    @State private var connectionsPath = NavigationPath()
    @State private var availabilityPath = NavigationPath()
    @State private var vaultPath = NavigationPath()

    enum Tab: Hashable { case connections, availability, vault, more }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $connectionsPath) {
                FolderView(app: app, folderId: nil).withRoutes(app)
            }
            .tabItem { Label("Connexions", systemImage: "rectangle.connected.to.line.below") }
            .tag(Tab.connections)

            NavigationStack(path: $availabilityPath) {
                AvailabilityView(app: app).withRoutes(app)
            }
            .tabItem { Label("Disponibilité", systemImage: "waveform.path.ecg") }
            .badge(downCount)
            .tag(Tab.availability)

            NavigationStack(path: $vaultPath) {
                VaultView(app: app).withRoutes(app)
            }
            .tabItem { Label("Coffre", systemImage: "key.fill") }
            .tag(Tab.vault)

            NavigationStack {
                MoreView(app: app)
            }
            .tabItem { Label("Plus", systemImage: "ellipsis.circle") }
            .tag(Tab.more)
        }
        .task { await app.refresh() }
        .fullScreenCover(item: $app.activeSession) { target in
            SessionView(target: target, app: app)
        }
    }

    private var downCount: Int {
        app.tree.entries.filter { $0.kind.opensNatively && app.status[$0.id].map { !$0.reachable } == true }.count
    }
}

extension View {
    func withRoutes(_ app: AppSession) -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .folder(let id): FolderView(app: app, folderId: id)
            case .entry(let id): EntryDetailView(app: app, entryId: id)
            case .credential(let id): CredentialDetailView(app: app, credentialId: id)
            }
        }
    }
}

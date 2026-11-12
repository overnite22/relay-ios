import RelayKit
import SwiftUI

/// Interface principale : onglets Connexions, Disponibilité, Coffre et Plus.
struct HomeView: View {
    @Bindable var app: AppSession
    @State private var tab = Tab.connections
    @State private var connectionsPath = NavigationPath()
    @State private var availabilityPath = NavigationPath()
    @State private var vaultPath = NavigationPath()

    enum Tab: Hashable { case connections, availability, commands, vault, more }

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

            NavigationStack {
                CommandsView(app: app).withRoutes(app)
            }
            .tabItem { Label("Commandes", systemImage: "terminal") }
            .tag(Tab.commands)

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
        .onChange(of: app.requestedTab) { _, requested in
            if requested == "commands" { tab = .commands }
            app.requestedTab = nil
        }
        .overlay(alignment: .bottom) {
            if !app.sessions.isEmpty && app.presentedSessionID == nil { sessionsPill }
        }
        .fullScreenCover(isPresented: Binding(
            get: { app.presentedSessionID != nil },
            set: { if !$0 { app.presentedSessionID = nil } }
        )) {
            SessionsHost(app: app)
        }
    }

    /// Retour aux sessions réduites.
    private var sessionsPill: some View {
        Button {
            app.presentedSessionID = app.sessions.last?.uid
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.stack.fill")
                Text(app.sessions.count == 1 ? (app.sessions.first?.title ?? "") : "\(app.sessions.count) sessions ouvertes")
                    .lineLimit(1)
                Image(systemName: "chevron.up").font(.caption.weight(.bold))
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.relayAccent.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 92)
        .accessibilityIdentifier("sessionsPill")
    }

    private var downCount: Int {
        app.tree.entries.filter { $0.kind.isMonitored && app.status[$0.id].map { !$0.reachable } == true }.count
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

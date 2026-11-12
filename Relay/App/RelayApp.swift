import RelayKit
import SwiftUI

@main struct RelayApp: App {
    @State private var app: AppSession
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        if let fixture = UITestSupport.session() {
            _app = State(initialValue: fixture)
            return
        }
        #endif
        _app = State(initialValue: AppSession(store: KeychainAccountStore()))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                switch app.phase {
                case .loading: ProgressView()
                case .unpaired: PairingView(app: app)
                case .paired: HomeView(app: app)
                }
                // Masque le contenu dans le sélecteur d'apps (secrets, inventaire).
                if scenePhase != .active && app.presentedSessionID == nil {
                    Rectangle().fill(.regularMaterial).ignoresSafeArea()
                        .overlay { Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.secondary) }
                }
            }
            .tint(.relayAccent)
            .task { app.restore() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, app.phase == .paired { Task { await app.refresh() } }
                if phase == .background { app.lockSecrets() }
            }
        }
    }
}

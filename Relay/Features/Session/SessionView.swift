import RelayKit
import SwiftUI

/// Pont SwiftUI vers l'écran distant UIKit.
struct RemoteScreen: UIViewRepresentable {
    let view: RemoteScreenView
    func makeUIView(context: Context) -> RemoteScreenView { view }
    func updateUIView(_ uiView: RemoteScreenView, context: Context) {}
}

/// Hôte plein écran : affiche la session choisie parmi celles ouvertes.
struct SessionsHost: View {
    let app: AppSession
    var body: some View {
        if let controller = app.presentedSession {
            SessionView(controller: controller, app: app).id(controller.uid)
        } else {
            Color.black.ignoresSafeArea()
        }
    }
}

/// Session plein écran (SSH, RDP, VNC, console Proxmox) avec barre d'outils.
struct SessionView: View {
    @Environment(\.displayScale) private var displayScale
    @Bindable var controller: SessionController
    let app: AppSession
    @State private var showHelp = false

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color.black.ignoresSafeArea()
                    RemoteScreen(view: controller.screen)
                        .onAppear { controller.viewResized(geo.size, scale: displayScale) }
                        .onChange(of: geo.size) { _, size in controller.viewResized(size, scale: displayScale) }
                    overlay
                }
            }
            .navigationTitle(controller.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar, .bottomBar)
            .toolbar { toolbar }
            .sheet(isPresented: $showHelp) { GestureHelpView() }
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
    }

    @ViewBuilder private var overlay: some View {
        switch controller.phase {
        case .preparing, .connecting:
            VStack(spacing: 12) {
                ProgressView().controlSize(.large).tint(.white)
                Text("Connexion à \(controller.target.title)…").foregroundStyle(.white)
                if controller.target.recording {
                    Label("Session enregistrée", systemImage: "record.circle").font(.caption).foregroundStyle(.red)
                }
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier("sessionConnecting")
        case .ended(let error):
            VStack(spacing: 14) {
                Image(systemName: error == nil ? "bolt.horizontal.circle" : "exclamationmark.triangle.fill")
                    .font(.system(size: 40)).foregroundStyle(error == nil ? Color.secondary : Color.orange)
                Text(error == nil ? "Session terminée" : "Session interrompue").font(.headline)
                if let error { Text(error).font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary) }
                HStack {
                    Button("Fermer") { app.closeSession(controller) }.buttonStyle(.bordered)
                    Button("Reconnecter", systemImage: "arrow.clockwise") { controller.reconnect() }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("sessionReconnect")
                }
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier("sessionEnded")
        case .connected:
            if let toast = controller.toast {
                VStack {
                    Spacer()
                    Text(toast).font(.callout).padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 16)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button("Fermer la session", systemImage: "xmark") { app.closeSession(controller) }.accessibilityIdentifier("sessionClose")
            Button("Réduire", systemImage: "chevron.down") { app.minimizeSessions() }.accessibilityIdentifier("sessionMinimize")
        }
        if app.sessions.count > 1 {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(app.sessions, id: \.uid) { session in
                        Button {
                            app.presentedSessionID = session.uid
                        } label: {
                            Label(session.title, systemImage: session.uid == controller.uid ? "checkmark" : session.target.kind.symbol)
                        }
                    }
                    Divider()
                    Button("Réduire toutes les sessions", systemImage: "chevron.down") { app.minimizeSessions() }
                } label: {
                    Label("Sessions (\(app.sessions.count))", systemImage: "square.stack")
                }
                .accessibilityIdentifier("sessionSwitcher")
            }
        }
        if controller.target.recording {
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "record.circle").foregroundStyle(.red).accessibilityLabel("Enregistrement en cours")
            }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button("Clavier", systemImage: controller.keyboardVisible ? "keyboard.chevron.compact.down" : "keyboard") {
                controller.toggleKeyboard()
            }
            .accessibilityIdentifier("sessionKeyboard")
            Spacer()
            Menu {
                Picker("Pointeur", selection: $controller.mode) {
                    ForEach(PointerMode.allCases) { mode in Label(mode.title, systemImage: mode.symbol).tag(mode) }
                }
                Button("Taille d'origine", systemImage: "arrow.down.right.and.arrow.up.left") { controller.resetZoom() }
            } label: {
                Label("Pointeur", systemImage: controller.mode.symbol)
            }
            .accessibilityIdentifier("sessionPointer")
            Spacer()
            Menu {
                Button("Envoyer le presse-papiers", systemImage: "doc.on.clipboard") { controller.sendClipboard() }
                Button("Taper le presse-papiers", systemImage: "keyboard.badge.ellipsis") { controller.typeClipboard() }
            } label: {
                Label("Presse-papiers", systemImage: "doc.on.clipboard")
            }
            .accessibilityIdentifier("sessionClipboard")
            Spacer()
            Menu {
                if controller.target.kind != .ssh {
                    Button("Ctrl+Alt+Suppr") { controller.sendCtrlAltDel() }
                    Button("Touche Windows") { controller.sendKey([], Keysym.superLeft) }
                    Button("Alt+Tab") { controller.sendKey([Keysym.altLeft], Keysym.tab) }
                }
                Button("Ctrl+C") { controller.sendKey([Keysym.controlLeft], 0x63) }
                Button("Ctrl+D") { controller.sendKey([Keysym.controlLeft], 0x64) }
                Button("Ctrl+Z") { controller.sendKey([Keysym.controlLeft], 0x7A) }
                Button("Échap") { controller.sendKey([], Keysym.escape) }
                Divider()
                Button("Reconnecter", systemImage: "arrow.clockwise") { controller.reconnect() }
                Button("Aide des gestes", systemImage: "questionmark.circle") { showHelp = true }
            } label: {
                Label("Plus", systemImage: "ellipsis.circle")
            }
            .accessibilityIdentifier("sessionMore")
        }
    }
}

struct GestureHelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Pavé tactile (RDP, VNC)") {
                    help("hand.draw", "Glisser un doigt", "Déplace le pointeur")
                    help("hand.tap", "Toucher", "Clic gauche au pointeur")
                    help("hand.tap.fill", "Toucher à deux doigts", "Clic droit")
                    help("hand.point.up.left", "Appui long puis glisser", "Glisser-déposer")
                    help("arrow.up.and.down", "Glisser à deux doigts", "Molette")
                }
                Section("Toucher direct (SSH)") {
                    help("hand.tap", "Toucher", "Clic à cet endroit")
                    help("hand.draw", "Glisser un doigt", "Sélectionner du texte (copié automatiquement)")
                    help("hand.point.up.left", "Appui long", "Clic droit")
                    help("arrow.up.and.down", "Glisser à deux doigts", "Défiler l'historique, ou déplacer la vue quand elle est zoomée")
                }
                Section("Partout") {
                    help("arrow.up.left.and.arrow.down.right", "Pincer", "Zoomer")
                    help("keyboard", "Bouton Clavier", "Clavier avec Échap, Tab, Ctrl, Alt, flèches et F1–F12")
                }
            }
            .navigationTitle("Gestes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("OK") { dismiss() } }
        }
    }

    private func help(_ symbol: String, _ gesture: String, _ effect: String) -> some View {
        Label {
            VStack(alignment: .leading) {
                Text(gesture).font(.body)
                Text(effect).font(.caption).foregroundStyle(.secondary)
            }
        } icon: { Image(systemName: symbol) }
    }
}

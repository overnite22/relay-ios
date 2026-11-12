import RelayKit
import SwiftUI
import UIKit

/// Ce qu'on ouvre : une entrée de l'inventaire ou une connexion rapide.
enum SessionTarget: Identifiable, Equatable {
    case entry(Entry, record: Bool)
    case quick(QuickConnectRequest, title: String)

    var id: String {
        switch self {
        case .entry(let e, let record): return "entry-\(e.id)-\(record)"
        case .quick(let q, _): return "quick-\(q.kind.rawValue)-\(q.host)-\(q.port)"
        }
    }

    var title: String {
        switch self {
        case .entry(let e, _): return e.name
        case .quick(_, let title): return title
        }
    }

    var kind: EntryKind {
        switch self {
        case .entry(let e, _): return e.kind
        case .quick(let q, _): return q.kind
        }
    }

    var recording: Bool {
        switch self {
        case .entry(_, let record): return record
        case .quick(let q, _): return q.record
        }
    }
}

/// Réglages d'affichage des sessions (Réglages de l'app).
enum SessionPreferences {
    static let sshTextKey = "sshTextSize"
    static let rdpResolutionKey = "rdpResolution"

    /// Multiplicateur de densité du texte SSH (plus petit = plus de colonnes).
    static var sshText: Double {
        let v = UserDefaults.standard.double(forKey: sshTextKey)
        return v == 0 ? 0.85 : v
    }

    /// Pixels distants par point d'écran pour RDP/VNC.
    static var rdpResolution: Double {
        let v = UserDefaults.standard.double(forKey: rdpResolutionKey)
        return v == 0 ? 1.5 : v
    }

    static func options(kind: EntryKind, viewSize: CGSize, displayScale: CGFloat, record: Bool) -> SessionOptions {
        let tz = TimeZone.current.identifier
        if kind == .ssh {
            let s = max(displayScale, 1)
            return SessionOptions(width: Int(viewSize.width * s), height: Int(viewSize.height * s),
                                  dpi: Int((96 * s * sshText).rounded()), timezone: tz, record: record)
        }
        let r = rdpResolution
        return SessionOptions(width: Int(viewSize.width * r), height: Int(viewSize.height * r), dpi: 96, timezone: tz, record: record)
    }
}

@MainActor @Observable final class SessionController {
    enum Phase: Equatable {
        case preparing
        case connecting
        case connected
        case ended(String?)
    }

    let target: SessionTarget
    let uid = UUID().uuidString
    private(set) var phase: Phase = .preparing
    private(set) var remoteName: String?
    private(set) var keyboardVisible = false
    private(set) var toast: String?
    var mode: PointerMode {
        didSet { screen.mode = mode }
    }

    @ObservationIgnored let screen = RemoteScreenView()
    @ObservationIgnored private var engine: GuacEngine?
    @ObservationIgnored private weak var app: AppSession?
    @ObservationIgnored private var lastSize = CGSize.zero
    @ObservationIgnored private var lastScale: CGFloat = 2
    @ObservationIgnored private var resizeTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init(target: SessionTarget, app: AppSession) {
        self.target = target
        self.app = app
        mode = target.kind == .ssh ? .direct : .touchpad
        screen.mode = mode
        screen.onKeyboardChange = { [weak self] visible in self?.keyboardVisible = visible }
    }

    var title: String { remoteName ?? target.title }

    func start(size: CGSize, scale: CGFloat) {
        guard phase == .preparing || isEnded, size.width > 10, size.height > 10 else { return }
        lastSize = size
        lastScale = scale
        phase = .connecting
        Task { await open() }
    }

    var isEnded: Bool {
        if case .ended = phase { return true }
        return false
    }

    private func open() async {
        guard let app, let client = app.client else {
            phase = .ended("Appareil non appairé.")
            return
        }
        let options = SessionPreferences.options(kind: target.kind, viewSize: lastSize, displayScale: lastScale, record: target.recording)
        do {
            let ticket: SessionTicket
            switch target {
            case .entry(let entry, _):
                var opts = options
                opts.native = entry.kind == .pve
                ticket = try await client.connect(entry.id, options: opts)
                app.noteOpened(entry.id)
            case .quick(var request, _):
                request.width = options.width
                request.height = options.height
                request.dpi = options.dpi
                request.timezone = options.timezone
                ticket = try await client.quickConnect(request)
            }
            guard let transport = app.makeTransport(ticket) else {
                phase = .ended("Adresse du tunnel invalide.")
                return
            }
            let engine = GuacEngine(transport: transport)
            engine.onFrame = { [weak self] frame in self?.screen.show(frame) }
            engine.onCursor = { [weak self] cursor in self?.screen.setCursor(cursor) }
            engine.onName = { [weak self] name in self?.remoteName = name }
            engine.onClipboard = { [weak self] text in
                UIPasteboard.general.string = text
                self?.flash("Presse-papiers distant copié")
            }
            engine.onState = { [weak self] state, error in self?.update(state, error: error) }
            screen.engine = engine
            self.engine = engine
            engine.start()
        } catch {
            phase = .ended(error.localizedDescription)
        }
    }

    private func update(_ state: GuacState, error: String?) {
        switch state {
        case .connected:
            phase = .connected
        case .disconnected:
            if !isEnded { phase = .ended(error) }
            _ = screen.resignFirstResponder()
        default:
            break
        }
    }

    func reconnect() {
        engine?.stop()
        engine = nil
        phase = .preparing
        start(size: lastSize, scale: lastScale)
    }

    func close() {
        resizeTask?.cancel()
        engine?.stop()
        engine = nil
        _ = screen.resignFirstResponder()
    }

    /// Rotation ou changement de taille : nouvelle résolution après une courte pause.
    func viewResized(_ size: CGSize, scale: CGFloat) {
        // La première taille valide démarre la session (onAppear peut survenir avant la mise en page).
        if phase == .preparing {
            start(size: size, scale: scale)
            return
        }
        guard size != lastSize, size.width > 10, size.height > 10 else { return }
        lastSize = size
        lastScale = scale
        guard phase == .connected, target.kind != .vnc, target.kind != .pve else { return }
        resizeTask?.cancel()
        resizeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, !Task.isCancelled else { return }
            let o = SessionPreferences.options(kind: self.target.kind, viewSize: size, displayScale: scale, record: false)
            self.engine?.resize(width: o.width, height: o.height)
        }
    }

    func toggleKeyboard() { screen.toggleKeyboard() }

    func sendCtrlAltDel() { engine?.chord([Keysym.controlLeft, Keysym.altLeft], Keysym.delete) }

    func sendKey(_ modifiers: [Int], _ keysym: Int) { engine?.chord(modifiers, keysym) }

    /// Copie le presse-papiers de l'iPhone vers la session distante.
    func sendClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            flash("Presse-papiers vide")
            return
        }
        engine?.clipboard(text)
        flash("Presse-papiers envoyé à la session")
    }

    /// Tape le contenu du presse-papiers comme au clavier (fonctionne partout, y compris aux invites de mot de passe).
    func typeClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            flash("Presse-papiers vide")
            return
        }
        engine?.type(text)
        flash("Texte saisi")
    }

    func resetZoom() { screen.resetZoom() }

    private func flash(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { self?.toast = nil }
        }
    }
}

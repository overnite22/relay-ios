import Foundation

/// Transport d'un tunnel Guacamole : WebSocket en production, flux scripté pour les tests.
public protocol GuacTransport: AnyObject, Sendable {
    var onText: (@Sendable (String) -> Void)? { get set }
    var onClose: (@Sendable (String?) -> Void)? { get set }
    func start()
    func send(_ text: String)
    func close()
}

/// Tunnel WebSocket Relay prêt à démarrer (URL et jeton d'appareil fixés à la création).
public final class RelayTunnelTransport: GuacTransport, @unchecked Sendable {
    private let tunnel = GuacTunnel()
    private let url: URL
    private let token: String

    public init(url: URL, deviceToken: String) {
        self.url = url
        token = deviceToken
    }

    public var onText: (@Sendable (String) -> Void)? {
        get { tunnel.onText }
        set { tunnel.onText = newValue }
    }

    public var onClose: (@Sendable (String?) -> Void)? {
        get { tunnel.onClose }
        set { tunnel.onClose = newValue }
    }

    public func start() { tunnel.open(url: url, token: token) }
    public func send(_ text: String) { tunnel.send(text) }
    public func close() { tunnel.close() }
}

/// Flux scripté : rejoue des instructions, ignore les envois (tests, démonstration).
public final class ScriptedTransport: GuacTransport, @unchecked Sendable {
    public var onText: (@Sendable (String) -> Void)?
    public var onClose: (@Sendable (String?) -> Void)?
    /// Réponses d'un faux serveur aux envois du client (tests de fichiers).
    public var respond: (@Sendable (String) -> [String])?
    private let script: [String]
    private let lock = NSLock()
    private var sentLog: [String] = []

    public init(script: [String]) { self.script = script }

    public var sent: [String] {
        lock.lock(); defer { lock.unlock() }
        return sentLog
    }

    public func start() {
        let script = self.script
        let deliver = onText
        DispatchQueue.global().async {
            for chunk in script { deliver?(chunk) }
        }
    }

    public func send(_ text: String) {
        lock.lock(); sentLog.append(text); lock.unlock()
        guard let replies = respond?(text), !replies.isEmpty else { return }
        let deliver = onText
        DispatchQueue.global().async {
            for reply in replies { deliver?(reply) }
        }
    }

    public func close() { onClose?(nil) }
}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Transport WebSocket du tunnel Guacamole (`/api/tunnel?token=…`), authentifié par le jeton d'appareil.
/// Les trames texte reçues sont transmises telles quelles ; l'appelant les donne à `GuacClientCore`.
public final class GuacTunnel: NSObject, @unchecked Sendable {
    public var onText: (@Sendable (String) -> Void)?
    public var onClose: (@Sendable (String?) -> Void)?

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private let lock = NSLock()
    private var closed = false

    public override init() { super.init() }

    public func open(url: URL, token: String) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        #if canImport(Darwin)
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        #else
        let session = URLSession(configuration: config)
        #endif
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("1", forHTTPHeaderField: "X-Relay")
        request.setValue("guacamole", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 16 << 20
        self.session = session
        self.task = task
        task.resume()
        receiveLoop()
    }

    public func send(_ text: String) {
        task?.send(.string(text)) { [weak self] error in
            if error != nil { self?.finish(reason: "Envoi impossible") }
        }
    }

    public func close() {
        lock.lock()
        let already = closed
        closed = true
        lock.unlock()
        task?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
        if !already { onClose?(nil) }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text): self.onText?(text)
                case .data(let data): if let text = String(data: data, encoding: .utf8) { self.onText?(text) }
                @unknown default: break
                }
                self.receiveLoop()
            case .failure(let error):
                self.finish(reason: (error as? URLError)?.localizedDescription ?? "Connexion perdue")
            }
        }
    }

    private func finish(reason: String?) {
        lock.lock()
        let already = closed
        closed = true
        lock.unlock()
        guard !already else { return }
        session?.invalidateAndCancel()
        onClose?(reason)
    }

}

// Les délégués WebSocket ne sont pas disponibles tels quels dans swift-corelibs-foundation (Linux, compilation seule).
#if canImport(Darwin)
extension GuacTunnel: URLSessionWebSocketDelegate {
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        finish(reason: nil)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(reason: error.localizedDescription) }
    }
}
#endif

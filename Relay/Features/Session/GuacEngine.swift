import CoreGraphics
import Foundation
import RelayKit

/// Moteur d'une session : protocole + rendu, confinés à une file série.
/// Les résultats (images, états) sont publiés sur le thread principal.
final class GuacEngine: @unchecked Sendable {
    struct Frame: @unchecked Sendable {
        let image: CGImage?
        let size: CGSize
    }

    struct Cursor: @unchecked Sendable {
        let image: CGImage?
        let hotspot: CGPoint
    }

    var onFrame: (@MainActor (Frame) -> Void)?
    var onCursor: (@MainActor (Cursor) -> Void)?
    var onState: (@MainActor (GuacState, String?) -> Void)?
    var onClipboard: (@MainActor (String) -> Void)?
    var onName: (@MainActor (String) -> Void)?
    var onFilesystem: (@MainActor (Int, String) -> Void)?
    var onFileReceived: (@MainActor (GuacClientCore.ReceivedFile) -> Void)?
    var onFileProgress: (@MainActor (String, Int) -> Void)?

    private let queue = DispatchQueue(label: "relay.guac.engine", qos: .userInteractive)
    private let core = GuacClientCore()
    private let display = GuacDisplay()
    private let transport: GuacTransport
    private var pingTimer: DispatchSourceTimer?
    private var lastError: String?

    init(transport: GuacTransport) {
        self.transport = transport
    }

    func start() {
        queue.async { [self] in
            core.onSend = { [weak self] text in self?.transport.send(text) }
            core.onDisplay = { [weak self] command in self?.handle(command) }
            core.onState = { [weak self] state in self?.publishState(state) }
            core.onError = { [weak self] error in self?.lastError = error.description }
            core.onClipboard = { [weak self] text in
                let callback = self?.onClipboard
                Task { @MainActor in callback?(text) }
            }
            core.onFilesystem = { [weak self] index, name in
                let callback = self?.onFilesystem
                Task { @MainActor in callback?(index, name) }
            }
            core.onFileReceived = { [weak self] file in
                let callback = self?.onFileReceived
                Task { @MainActor in callback?(file) }
            }
            core.onFileProgress = { [weak self] name, bytes in
                let callback = self?.onFileProgress
                Task { @MainActor in callback?(name, bytes) }
            }
            core.onName = { [weak self] name in
                let callback = self?.onName
                Task { @MainActor in callback?(name) }
            }
            transport.onText = { [weak self] text in
                guard let self else { return }
                self.queue.async { self.core.receive(text) }
            }
            transport.onClose = { [weak self] reason in
                guard let self else { return }
                self.queue.async {
                    if self.lastError == nil, let reason, self.core.state != .disconnected, self.core.state != .disconnecting {
                        self.lastError = reason
                    }
                    self.core.tunnelClosed()
                }
            }
            core.connecting()
            transport.start()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 5, repeating: 5)
            timer.setEventHandler { [weak self] in self?.core.ping() }
            timer.resume()
            pingTimer = timer
        }
    }

    func stop() {
        queue.async { [self] in
            pingTimer?.cancel()
            pingTimer = nil
            core.disconnect()
            transport.close()
        }
    }

    // MARK: - Entrées

    func mouse(x: Int, y: Int, buttons: MouseButtons) { queue.async { self.core.sendMouse(x: x, y: y, buttons: buttons) } }
    func key(_ keysym: Int, pressed: Bool) { queue.async { self.core.sendKey(keysym, pressed: pressed) } }
    func tap(_ keysym: Int) { queue.async { self.core.tapKey(keysym) } }
    func type(_ text: String) { queue.async { self.core.type(text) } }
    func clipboard(_ text: String) { queue.async { self.core.sendClipboard(text) } }
    func resize(width: Int, height: Int) { queue.async { self.core.sendSize(width: width, height: height) } }

    // MARK: - Fichiers

    func requestObject(_ object: Int, name: String, progress: (@MainActor (Int) -> Void)? = nil,
                       completion: @escaping @MainActor (GuacClientCore.ObjectResult) -> Void) {
        queue.async {
            self.core.requestObject(object, name: name, progress: { bytes in
                Task { @MainActor in progress?(bytes) }
            }, completion: { result in
                Task { @MainActor in completion(result) }
            })
        }
    }

    func putObject(_ object: Int, name: String, mimetype: String, data: Data, progress: (@MainActor (Int) -> Void)? = nil,
                   completion: @escaping @MainActor (Result<Void, GuacError>) -> Void) {
        queue.async {
            self.core.putObject(object, name: name, mimetype: mimetype, data: data, progress: { bytes in
                Task { @MainActor in progress?(bytes) }
            }, completion: { result in
                Task { @MainActor in completion(result) }
            })
        }
    }

    /// Combinaison : modificateurs enfoncés, touche, puis relâchement inverse.
    func chord(_ modifiers: [Int], _ keysym: Int) {
        queue.async {
            for m in modifiers { self.core.sendKey(m, pressed: true) }
            self.core.tapKey(keysym)
            for m in modifiers.reversed() { self.core.sendKey(m, pressed: false) }
        }
    }

    // MARK: - File interne

    private func handle(_ command: DisplayCommand) {
        if case .sync(let timestamp) = command {
            let frame = Frame(image: display.composite(), size: display.size)
            let callback = onFrame
            Task { @MainActor in callback?(frame) }
            core.acknowledgeSync(timestamp)
            return
        }
        if display.apply(command) {
            let cursor = Cursor(image: display.cursorImage, hotspot: display.cursorHotspot)
            let callback = onCursor
            Task { @MainActor in callback?(cursor) }
        }
    }

    private func publishState(_ state: GuacState) {
        let error = state == .disconnected ? lastError : nil
        if state == .disconnected {
            pingTimer?.cancel()
            pingTimer = nil
        }
        let callback = onState
        Task { @MainActor in callback?(state, error) }
    }
}

import Foundation

public enum GuacState: Equatable, Sendable {
    case idle, connecting, waiting, connected, disconnecting, disconnected
}

public struct GuacError: Error, Equatable, Sendable {
    public let message: String
    public let status: Int

    public init(message: String, status: Int) {
        self.message = message
        self.status = status
    }

    /// Libellé lisible d'après le code d'état Guacamole.
    public var description: String {
        switch status {
        case 0x0200: return "Le serveur guacd ne peut pas ouvrir la session : \(message)"
        case 0x0201: return "Service occupé, réessayez : \(message)"
        case 0x0202: return "Délai dépassé côté serveur : \(message)"
        case 0x0203: return "Erreur du serveur distant : \(message)"
        case 0x0301: return "Non autorisé : \(message)"
        case 0x0303: return "Accès refusé : \(message)"
        case 0x0308: return "Session fermée pour inactivité."
        case 0x031D: return "Trop de sessions ouvertes."
        default: return message.isEmpty ? "Session interrompue (code \(status))." : message
        }
    }
}

/// Cœur du client Guacamole : interprète les instructions reçues, produit des commandes d'affichage
/// et les instructions à renvoyer. Indépendant de l'UI ; à utiliser depuis une seule file (acteur ou MainActor).
public final class GuacClientCore {
    public private(set) var state: GuacState = .idle
    public private(set) var tunnelID: String?
    public private(set) var name: String?

    public var onDisplay: ((DisplayCommand) -> Void)?
    public var onState: ((GuacState) -> Void)?
    public var onName: ((String) -> Void)?
    public var onClipboard: ((String) -> Void)?
    public var onError: ((GuacError) -> Void)?
    /// Système de fichiers proposé par guacd (SFTP en SSH, lecteur en RDP) : index d'objet et nom.
    public var onFilesystem: ((Int, String) -> Void)?
    /// Fichier poussé par le serveur (RDP : copie dans le dossier Download du lecteur).
    public var onFileReceived: ((ReceivedFile) -> Void)?
    /// Progression d'un fichier poussé par le serveur (nom, octets reçus).
    public var onFileProgress: ((String, Int) -> Void)?
    /// Texte à écrire sur le tunnel.
    public var onSend: ((String) -> Void)?

    private var parser = GuacParser()
    private var streams: [Int: Stream] = [:]
    private var nextOutputStream = 0
    private var lastSync = 0

    private enum Stream {
        case image(layer: Int, mask: Int, x: Int, y: Int, mime: String, data: Data)
        case clipboard(mime: String, data: Data)
        case object(request: Int, mime: String, data: Data)
        case file(name: String, mime: String, data: Data)
        case ignored
    }

    public struct ReceivedFile: Equatable, Sendable {
        public let name: String
        public let mimetype: String
        public let data: Data
    }

    /// Réponse à une lecture d'objet : type MIME et contenu.
    public typealias ObjectResult = Result<(mimetype: String, data: Data), GuacError>

    private struct PendingGet {
        let id: Int
        let object: Int
        let name: String
        let progress: ((Int) -> Void)?
        let completion: (ObjectResult) -> Void
    }

    private struct PendingPut {
        let data: Data
        var offset: Int
        var ended: Bool
        let progress: ((Int) -> Void)?
        let completion: (Result<Void, GuacError>) -> Void
    }

    private var gets: [PendingGet] = []
    private var getsByStream: [Int: PendingGet] = [:]
    private var puts: [Int: PendingPut] = [:]
    private var nextRequest = 0
    /// Taille des blocs envoyés (comme guacamole-common-js).
    public static let blobSize = 6048
    /// Type MIME d'un index de dossier.
    public static let directoryMimetype = "application/vnd.glyptodon.guacamole.stream-index+json"

    public init() {}

    // MARK: - Cycle de vie

    public func connecting() { set(.connecting) }

    /// Données reçues du tunnel (une ou plusieurs instructions, éventuellement partielles).
    public func receive(_ text: String) {
        let instructions: [GuacInstruction]
        do { instructions = try parser.feed(text) } catch {
            fail(GuacError(message: "Flux Guacamole illisible", status: 0x0203))
            return
        }
        for instruction in instructions { handle(instruction) }
    }

    /// Le tunnel est fermé (par le serveur ou le réseau).
    public func tunnelClosed() {
        if state != .disconnected { set(.disconnected) }
    }

    public func disconnect() {
        guard state != .disconnected, state != .disconnecting else { return }
        set(.disconnecting)
        send(GuacInstruction("disconnect"))
        set(.disconnected)
    }

    // MARK: - Envois

    public func sendMouse(x: Int, y: Int, buttons: MouseButtons) {
        guard state == .connected else { return }
        send(GuacInstruction("mouse", String(x), String(y), String(buttons.rawValue)))
    }

    public func sendKey(_ keysym: Int, pressed: Bool) {
        guard state == .connected, keysym != 0 else { return }
        send(GuacInstruction("key", String(keysym), pressed ? "1" : "0"))
    }

    /// Appui puis relâchement d'une touche.
    public func tapKey(_ keysym: Int) {
        sendKey(keysym, pressed: true)
        sendKey(keysym, pressed: false)
    }

    /// Frappe d'un texte, chaque caractère étant converti en keysym.
    public func type(_ text: String) {
        for keysym in Keysym.sequence(for: text) { tapKey(keysym) }
    }

    public func sendSize(width: Int, height: Int) {
        guard state == .connected || state == .waiting else { return }
        send(GuacInstruction("size", String(width), String(height)))
    }

    /// Envoie le presse-papiers local (texte) au serveur distant.
    public func sendClipboard(_ text: String) {
        guard state == .connected else { return }
        let index = nextOutputStream
        nextOutputStream += 1
        send(GuacInstruction("clipboard", String(index), "text/plain"))
        let bytes = Array(text.utf8)
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + 6048, bytes.count)
            send(GuacInstruction("blob", String(index), Data(bytes[offset..<end]).base64EncodedString()))
            offset = end
        }
        send(GuacInstruction("end", String(index)))
    }

    // MARK: - Fichiers (objets Guacamole)

    /// Demande le contenu d'un chemin de l'objet (dossier : index JSON ; fichier : octets).
    public func requestObject(_ object: Int, name: String, progress: ((Int) -> Void)? = nil,
                              completion: @escaping (ObjectResult) -> Void) {
        guard state == .connected else {
            completion(.failure(GuacError(message: "Session non connectée", status: 0x0300)))
            return
        }
        nextRequest += 1
        gets.append(PendingGet(id: nextRequest, object: object, name: name, progress: progress, completion: completion))
        send(GuacInstruction("get", String(object), name))
    }

    /// Envoie un fichier vers `name` dans l'objet ; chaque bloc attend l'accusé du serveur.
    public func putObject(_ object: Int, name: String, mimetype: String, data: Data, progress: ((Int) -> Void)? = nil,
                          completion: @escaping (Result<Void, GuacError>) -> Void) {
        guard state == .connected else {
            completion(.failure(GuacError(message: "Session non connectée", status: 0x0300)))
            return
        }
        let index = nextOutputStream
        nextOutputStream += 1
        puts[index] = PendingPut(data: data, offset: 0, ended: false, progress: progress, completion: completion)
        send(GuacInstruction("put", String(object), String(index), mimetype, name))
    }

    /// Abandonne les transferts en cours (session fermée).
    private func failTransfers(_ error: GuacError) {
        let pendingGets = gets + Array(getsByStream.values)
        let pendingPuts = Array(puts.values)
        gets.removeAll()
        getsByStream.removeAll()
        puts.removeAll()
        for g in pendingGets { g.completion(.failure(error)) }
        for p in pendingPuts { p.completion(.failure(error)) }
    }

    private func handleAck(stream: Int, message: String, status: Int) {
        guard var put = puts[stream] else { return }
        if status != 0 {
            puts.removeValue(forKey: stream)
            put.completion(.failure(GuacError(message: message.isEmpty ? "Envoi refusé" : message, status: status)))
            return
        }
        if put.ended {
            puts.removeValue(forKey: stream)
            put.completion(.success(()))
            return
        }
        if put.offset >= put.data.count {
            put.ended = true
            puts[stream] = put
            send(GuacInstruction("end", String(stream)))
            // guacd n'accuse pas toujours la fin : le transfert est terminé côté client.
            puts.removeValue(forKey: stream)
            put.completion(.success(()))
            return
        }
        let end = min(put.offset + Self.blobSize, put.data.count)
        let chunk = put.data.subdata(in: put.offset..<end)
        put.offset = end
        puts[stream] = put
        send(GuacInstruction("blob", String(stream), chunk.base64EncodedString()))
        put.progress?(end)
    }

    /// Instruction de maintien du tunnel (toutes les 5 s, comme le client web).
    public func ping() {
        send(GuacInstruction("", "ping", String(Int(Date().timeIntervalSince1970 * 1000))))
    }

    /// À appeler une fois la trame `sync` rendue à l'écran.
    public func acknowledgeSync(_ timestamp: Int) {
        send(GuacInstruction("sync", String(timestamp)))
    }

    // MARK: - Réception

    private func handle(_ i: GuacInstruction) {
        switch i.opcode {
        case "":
            // Messages internes du tunnel : identifiant, ou écho d'un ping.
            if i.string(0) == "ping" { return }
            if i.string(0) == "relay-error" { return }
            tunnelID = i.string(0)
            if state == .connecting { set(.waiting) }
        case "sync":
            lastSync = i.int(0)
            if state == .waiting || state == .connecting { set(.connected) }
            onDisplay?(.sync(timestamp: lastSync))
        case "nop", "ready", "required", "argv", "msg", "set":
            if i.opcode == "argv" { ack(i.int(0), "Unsupported", 0x0100) }
            if i.opcode == "set" { return }
        case "filesystem":
            onFilesystem?(i.int(0), i.string(1))
        case "body":
            // body,<objet>,<flux>,<type>,<nom> : réponse à un get.
            let object = i.int(0), stream = i.int(1), mime = i.string(2), name = i.string(3)
            guard let index = gets.firstIndex(where: { $0.object == object && $0.name == name }) else {
                ack(stream, "Unexpected", 0x0100)
                return
            }
            let request = gets.remove(at: index)
            getsByStream[stream] = request
            streams[stream] = .object(request: request.id, mime: mime, data: Data())
            ack(stream, "OK", 0)
        case "ack":
            handleAck(stream: i.int(0), message: i.string(1), status: i.int(2))
        case "error":
            fail(GuacError(message: i.string(0), status: i.int(1)))
        case "disconnect":
            set(.disconnected)
        case "name":
            name = i.string(0)
            onName?(i.string(0))
        case "size":
            onDisplay?(.size(layer: i.int(0), width: i.int(1), height: i.int(2)))
        case "img":
            streams[i.int(0)] = .image(layer: i.int(2), mask: i.int(1), x: i.int(4), y: i.int(5), mime: i.string(3), data: Data())
        case "png", "jpeg", "webp":
            let mime = i.opcode == "png" ? "image/png" : (i.opcode == "jpeg" ? "image/jpeg" : "image/webp")
            onDisplay?(.image(layer: i.int(1), mask: i.int(0), x: i.int(2), y: i.int(3), mime: mime, data: Data(base64Encoded: i.string(4)) ?? Data()))
        case "blob":
            let index = i.int(0)
            guard let stream = streams[index] else { return }
            let chunk = Data(base64Encoded: i.string(1)) ?? Data()
            switch stream {
            case .image(let layer, let mask, let x, let y, let mime, var data):
                data.append(chunk)
                streams[index] = .image(layer: layer, mask: mask, x: x, y: y, mime: mime, data: data)
            case .clipboard(let mime, var data):
                data.append(chunk)
                streams[index] = .clipboard(mime: mime, data: data)
            case .object(let request, let mime, var data):
                data.append(chunk)
                streams[index] = .object(request: request, mime: mime, data: data)
                getsByStream[index]?.progress?(data.count)
            case .file(let name, let mime, var data):
                data.append(chunk)
                streams[index] = .file(name: name, mime: mime, data: data)
                onFileProgress?(name, data.count)
            case .ignored:
                break
            }
            ack(index, "OK", 0)
        case "end":
            let index = i.int(0)
            guard let stream = streams.removeValue(forKey: index) else { return }
            switch stream {
            case .image(let layer, let mask, let x, let y, let mime, let data):
                onDisplay?(.image(layer: layer, mask: mask, x: x, y: y, mime: mime, data: data))
            case .clipboard(let mime, let data):
                if mime.hasPrefix("text/"), let text = String(data: data, encoding: .utf8) { onClipboard?(text) }
            case .object(_, let mime, let data):
                getsByStream.removeValue(forKey: index)?.completion(.success((mimetype: mime, data: data)))
            case .file(let name, let mime, let data):
                onFileReceived?(ReceivedFile(name: name, mimetype: mime, data: data))
            case .ignored:
                break
            }
        case "clipboard":
            streams[i.int(0)] = .clipboard(mime: i.string(1), data: Data())
        case "file":
            // file,<flux>,<type>,<nom> : téléchargement poussé par le serveur.
            streams[i.int(0)] = .file(name: i.string(2), mime: i.string(1), data: Data())
            ack(i.int(0), "OK", 0)
        case "audio", "video", "pipe":
            streams[i.int(0)] = .ignored
            ack(i.int(0), "Unsupported", 0x0100)
        case "copy":
            onDisplay?(.copy(src: i.int(0), sx: i.int(1), sy: i.int(2), width: i.int(3), height: i.int(4), mask: i.int(5), dst: i.int(6), dx: i.int(7), dy: i.int(8)))
        case "transfer":
            onDisplay?(.transfer(src: i.int(0), sx: i.int(1), sy: i.int(2), width: i.int(3), height: i.int(4), function: i.int(5), dst: i.int(6), dx: i.int(7), dy: i.int(8)))
        case "rect":
            onDisplay?(.rect(layer: i.int(0), x: i.int(1), y: i.int(2), width: i.int(3), height: i.int(4)))
        case "start":
            onDisplay?(.start(layer: i.int(0), x: i.int(1), y: i.int(2)))
        case "line":
            onDisplay?(.line(layer: i.int(0), x: i.int(1), y: i.int(2)))
        case "curve":
            onDisplay?(.curve(layer: i.int(0), cp1x: i.int(1), cp1y: i.int(2), cp2x: i.int(3), cp2y: i.int(4), x: i.int(5), y: i.int(6)))
        case "arc":
            onDisplay?(.arc(layer: i.int(0), x: i.int(1), y: i.int(2), radius: i.int(3), start: i.double(4), end: i.double(5), negative: i.int(6) != 0))
        case "close":
            onDisplay?(.close(layer: i.int(0)))
        case "clip":
            onDisplay?(.clip(layer: i.int(0)))
        case "push":
            onDisplay?(.push(layer: i.int(0)))
        case "pop":
            onDisplay?(.pop(layer: i.int(0)))
        case "reset":
            onDisplay?(.reset(layer: i.int(0)))
        case "identity":
            onDisplay?(.identity(layer: i.int(0)))
        case "transform":
            onDisplay?(.transform(layer: i.int(0), a: i.double(1), b: i.double(2), c: i.double(3), d: i.double(4), e: i.double(5), f: i.double(6)))
        case "distort":
            onDisplay?(.distort(layer: i.int(0), a: i.double(1), b: i.double(2), c: i.double(3), d: i.double(4), e: i.double(5), f: i.double(6)))
        case "cfill":
            onDisplay?(.cfill(layer: i.int(1), mask: i.int(0), r: i.int(2), g: i.int(3), b: i.int(4), a: i.int(5)))
        case "cstroke":
            onDisplay?(.cstroke(layer: i.int(1), mask: i.int(0), cap: i.int(2), join: i.int(3), thickness: i.int(4), r: i.int(5), g: i.int(6), b: i.int(7), a: i.int(8)))
        case "lfill":
            onDisplay?(.lfill(layer: i.int(1), mask: i.int(0), src: i.int(2)))
        case "lstroke":
            onDisplay?(.lstroke(layer: i.int(1), mask: i.int(0), cap: i.int(2), join: i.int(3), thickness: i.int(4), src: i.int(5)))
        case "dispose":
            onDisplay?(.dispose(layer: i.int(0)))
        case "move":
            onDisplay?(.move(layer: i.int(0), parent: i.int(1), x: i.int(2), y: i.int(3), z: i.int(4)))
        case "shade":
            onDisplay?(.shade(layer: i.int(0), opacity: i.int(1)))
        case "cursor":
            onDisplay?(.cursor(hotX: i.int(0), hotY: i.int(1), src: i.int(2), sx: i.int(3), sy: i.int(4), width: i.int(5), height: i.int(6)))
        default:
            break
        }
    }

    private func ack(_ stream: Int, _ message: String, _ status: Int) {
        send(GuacInstruction("ack", String(stream), message, String(status)))
    }

    private func send(_ instruction: GuacInstruction) { onSend?(instruction.encoded()) }

    private func set(_ s: GuacState) {
        guard s != state else { return }
        state = s
        if s == .disconnected { failTransfers(GuacError(message: "Session fermée", status: 0x0209)) }
        onState?(s)
    }

    private func fail(_ error: GuacError) {
        onError?(error)
        set(.disconnected)
    }
}

import Foundation

/// Enregistrement de session conservé par le serveur (propre à l'utilisateur).
public struct Recording: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let kind: EntryKind
    public let at: String
    public let size: Int
    public let limited: Bool

    public init(id: String, name: String, kind: EntryKind, at: String, size: Int, limited: Bool) {
        self.id = id
        self.name = name
        self.kind = kind
        self.at = at
        self.size = size
        self.limited = limited
    }
}

/// Chronologie d'un enregistrement : trames d'affichage délimitées par `sync`.
public struct RecordingTimeline: Sendable {
    public struct Frame: Sendable {
        /// Millisecondes depuis le début de l'enregistrement.
        public let time: Int
        public let commands: [DisplayCommand]
    }

    public let frames: [Frame]

    /// Durée totale en millisecondes.
    public var duration: Int { frames.last?.time ?? 0 }

    public init(frames: [Frame]) { self.frames = frames }

    /// Décode le flux brut ; les instructions après le dernier `sync` forment une trame finale.
    public static func decode(_ data: Data) throws -> RecordingTimeline {
        guard let text = String(data: data, encoding: .utf8) else { throw GuacParseError.malformed("encodage") }
        let core = GuacClientCore()
        var frames: [Frame] = []
        var pending: [DisplayCommand] = []
        var origin: Int?
        var last = 0
        core.onDisplay = { command in
            if case .sync(let stamp) = command {
                let start = origin ?? stamp
                origin = start
                last = max(last, stamp - start)
                frames.append(Frame(time: last, commands: pending))
                pending.removeAll(keepingCapacity: true)
            } else {
                pending.append(command)
            }
        }
        var failure: GuacError?
        core.onError = { failure = $0 }
        // Découpage par morceaux pour limiter les copies sur les gros fichiers.
        var index = text.startIndex
        let chunk = 1 << 20
        while index < text.endIndex {
            let end = text.index(index, offsetBy: chunk, limitedBy: text.endIndex) ?? text.endIndex
            core.receive(String(text[index..<end]))
            if failure != nil { throw GuacParseError.malformed("flux illisible") }
            index = end
        }
        if !pending.isEmpty { frames.append(Frame(time: last, commands: pending)) }
        return RecordingTimeline(frames: frames)
    }

    /// Indice de la dernière trame dont l'heure est ≤ `time`.
    public func frameIndex(at time: Int) -> Int {
        guard !frames.isEmpty else { return -1 }
        var low = 0
        var high = frames.count - 1
        if frames[0].time > time { return 0 }
        while low < high {
            let mid = (low + high + 1) / 2
            if frames[mid].time <= time { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Attente réelle avant la trame `index` (pauses longues raccourcies si demandé).
    public func delay(before index: Int, speed: Double, skipIdle: Bool) -> Double {
        guard index > 0, index < frames.count else { return 0 }
        var gap = Double(frames[index].time - frames[index - 1].time) / 1000
        if skipIdle { gap = min(gap, 1) }
        return max(0, gap / max(speed, 0.1))
    }
}

extension RecordingTimeline {
    /// Format « m:ss » ou « h:mm:ss ».
    public static func clock(_ milliseconds: Int) -> String {
        let total = max(0, milliseconds / 1000)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

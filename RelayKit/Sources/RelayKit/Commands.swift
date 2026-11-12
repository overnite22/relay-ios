import Foundation

/// Résultat d'une commande sur un serveur.
public struct RunResult: Codable, Identifiable, Sendable, Hashable {
    public enum Status: String, Codable, Sendable {
        case pending, running, ok, failed, error, canceled, unknown

        public init(from decoder: Decoder) throws {
            self = Status(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }

        public var title: String {
            switch self {
            case .pending: return "En attente"
            case .running: return "En cours"
            case .ok: return "Réussie"
            case .failed: return "Échec"
            case .error: return "Erreur"
            case .canceled: return "Annulée"
            case .unknown: return "Inconnu"
            }
        }

        public var isFinal: Bool { self != .pending && self != .running }
    }

    public let entryId: String
    public let name: String
    public let address: String
    public let status: Status
    public let exitCode: Int?
    public let output: String
    public let truncated: Bool
    public let error: String
    public let durationMs: Double
    public let fingerprint: String
    public let newHostKey: Bool

    public var id: String { entryId }

    /// Vrai si la clé du serveur a changé : la commande a été refusée par précaution.
    public var hostKeyChanged: Bool { error.localizedCaseInsensitiveContains("clé") && status == .error }
}

/// Exécution d'une commande sur plusieurs serveurs (suivie, puis conservée dans l'historique).
public struct CommandRun: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let at: String
    public let finishedAt: String?
    public let user: String
    public let command: String
    public let sudo: Bool
    public let targets: Int
    public let ok: Int
    public let failed: Int
    public let results: [RunResult]?

    public var finished: Bool { finishedAt != nil }
}

public struct SavedCommand: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var command: String
    public var sudo: Bool

    public init(id: String = "", name: String, command: String, sudo: Bool) {
        self.id = id
        self.name = name
        self.command = command
        self.sudo = sudo
    }
}

public struct RunRequest: Codable, Sendable, Equatable {
    public var entryIds: [String]
    public var command: String
    public var sudo: Bool
    public var timeoutSec: Int
    public var concurrency: Int

    public init(entryIds: [String], command: String, sudo: Bool, timeoutSec: Int = 30, concurrency: Int = 10) {
        self.entryIds = entryIds
        self.command = command
        self.sudo = sudo
        self.timeoutSec = timeoutSec
        self.concurrency = concurrency
    }
}

extension RelayClient {
    public func startRun(_ request: RunRequest) async throws -> CommandRun {
        try await postJSON("/api/commands/run", request)
    }

    public func run(_ id: String) async throws -> CommandRun {
        try await getJSON("/api/commands/runs/\(pathEscape(id))")
    }

    public func cancelRun(_ id: String) async throws {
        try await sendEmpty("POST", "/api/commands/runs/\(pathEscape(id))/cancel", body: Data("{}".utf8))
    }

    public func runHistory(limit: Int = 50) async throws -> [CommandRun] {
        try await getJSON("/api/commands/runs", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    public func savedCommands() async throws -> [SavedCommand] {
        try await getJSON("/api/commands/saved")
    }

    public func saveCommand(_ command: SavedCommand) async throws -> SavedCommand {
        struct Body: Encodable { let name: String; let command: String; let sudo: Bool }
        let body = Body(name: command.name, command: command.command, sudo: command.sudo)
        if command.id.isEmpty { return try await postJSON("/api/commands/saved", body) }
        return try await putJSON("/api/commands/saved/\(pathEscape(command.id))", body)
    }

    public func deleteSavedCommand(_ id: String) async throws {
        try await sendEmpty("DELETE", "/api/commands/saved/\(pathEscape(id))")
    }

    /// Oublie la clé SSH mémorisée d'un serveur (après un changement de clé légitime).
    public func forgetHostKey(address: String) async throws {
        struct Body: Encodable { let address: String }
        try await sendEmpty("POST", "/api/known-hosts/forget", body: try JSONEncoder().encode(Body(address: address)))
    }
}

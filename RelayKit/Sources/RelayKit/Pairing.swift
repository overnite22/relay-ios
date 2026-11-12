import Foundation

/// Compte enregistré dans le Keychain : serveur Relay et jeton d'appareil.
public struct ServerAccount: Codable, Sendable, Equatable {
    public let server: URL
    public let token: String

    public init(server: URL, token: String) {
        self.server = server
        self.token = token
    }

    public var serverDisplay: String { server.host ?? server.absoluteString }
}

public enum PairingError: Error, Equatable, LocalizedError {
    case notPairingCode
    case invalidServer
    case insecureServer
    case invalidToken

    public var errorDescription: String? {
        switch self {
        case .notPairingCode: return "Ce QR code n'est pas un code d'appairage Relay."
        case .invalidServer: return "Adresse du serveur invalide (ex. https://relay.example.com)."
        case .insecureServer: return "Le serveur doit être en HTTPS."
        case .invalidToken: return "Jeton invalide : il commence par « rlt_ »."
        }
    }
}

/// Lecture du QR code « relay://pair?server=…&token=… » et validation de la saisie manuelle.
public enum Pairing {
    public static let tokenPrefix = "rlt_"

    public static func parse(code: String) throws -> ServerAccount {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed), components.scheme == "relay", components.host == "pair" else {
            throw PairingError.notPairingCode
        }
        let items = components.queryItems ?? []
        let server = items.first { $0.name == "server" }?.value ?? ""
        let token = items.first { $0.name == "token" }?.value ?? ""
        return try account(server: server, token: token)
    }

    public static func account(server: String, token: String) throws -> ServerAccount {
        let url = try serverURL(server)
        let tok = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard tok.hasPrefix(tokenPrefix), tok.count >= 36, tok.count <= 160,
              tok.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else {
            throw PairingError.invalidToken
        }
        return ServerAccount(server: url, token: tok)
    }

    /// Normalise l'adresse : schéma https imposé (http toléré pour localhost), pas de chemin ni d'identifiants.
    public static func serverURL(_ text: String) throws -> URL {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw PairingError.invalidServer }
        if !raw.contains("://") { raw = "https://" + raw }
        guard var components = URLComponents(string: raw), let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else {
            throw PairingError.invalidServer
        }
        let local = host == "localhost" || host == "127.0.0.1" || host == "::1"
        switch components.scheme?.lowercased() {
        case "https": break
        case "http" where local: break
        case "http": throw PairingError.insecureServer
        default: throw PairingError.invalidServer
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw PairingError.invalidServer }
        return url
    }
}

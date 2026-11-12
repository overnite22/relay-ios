import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum RelayError: Error, LocalizedError, Equatable {
    case unauthorized
    case forbidden(String)
    case notFound
    case server(String)
    case transport(String)
    case invalidResponse
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unauthorized: return "Appareil non autorisé : le jeton a été révoqué ou le serveur demande une connexion SSO."
        case .forbidden(let m): return m.isEmpty ? "Accès refusé." : m
        case .notFound: return "Introuvable sur le serveur."
        case .server(let m): return m
        case .transport(let m): return "Serveur injoignable : \(m)"
        case .invalidResponse: return "Réponse inattendue du serveur."
        case .cancelled: return "Annulé."
        }
    }
}

/// Transport HTTP injectable (URLSession en production, réponses synthétiques dans les tests).
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionTransport: HTTPTransport {
    let session: URLSession
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

/// Refuse les redirections : le jeton ne doit jamais partir vers un autre hôte.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Client de l'API Relay, authentifié par jeton d'appareil (Authorization: Bearer rlt_…).
public actor RelayClient {
    public let account: ServerAccount
    private let transport: HTTPTransport

    public init(account: ServerAccount, transport: HTTPTransport? = nil) {
        self.account = account
        if let transport {
            self.transport = transport
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil
            config.urlCache = nil
            config.httpAdditionalHeaders = nil
            #if !canImport(FoundationNetworking)
            config.waitsForConnectivity = false
            #endif
            config.timeoutIntervalForRequest = 30
            self.transport = URLSessionTransport(session: URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil))
        }
    }

    public static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    // MARK: - Requêtes

    nonisolated public func request(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil) throws -> URLRequest {
        guard var components = URLComponents(url: account.server, resolvingAgainstBaseURL: false) else { throw RelayError.invalidResponse }
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw RelayError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
        request.setValue("1", forHTTPHeaderField: "X-Relay")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw RelayError.cancelled }
            throw RelayError.transport((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
        guard let http = response as? HTTPURLResponse else { throw RelayError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw RelayError.unauthorized
        case 403: throw RelayError.forbidden(Self.message(in: data))
        case 404: throw RelayError.notFound
        default: throw RelayError.server(Self.message(in: data, fallback: "Erreur serveur (HTTP \(http.statusCode))."))
        }
    }

    private static func message(in data: Data, fallback: String = "") -> String {
        struct ErrorBody: Decodable { let error: String }
        return (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? fallback
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try decode(await send(request("GET", path, query: query)))
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, _ body: B) async throws -> T {
        try decode(await send(request("POST", path, body: JSONEncoder().encode(body))))
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw RelayError.invalidResponse }
    }

    // MARK: - API

    public func me() async throws -> ServerInfo { try await get("/api/me") }

    public func tree() async throws -> Tree { try await get("/api/tree") }

    public func connectionStatus() async throws -> [String: ConnectionTest] { try await get("/api/connection-status") }

    public func entry(_ id: String) async throws -> Entry { try await get("/api/entries/\(escape(id))") }

    public func testConnection(_ id: String) async throws -> ConnectionTest {
        try decode(await send(request("POST", "/api/entries/\(escape(id))/test-connection")))
    }

    public func connect(_ id: String, options: SessionOptions) async throws -> SessionTicket {
        try await post("/api/entries/\(escape(id))/connect", options)
    }

    public func quickConnect(_ req: QuickConnectRequest) async throws -> SessionTicket {
        try await post("/api/quick-connect", req)
    }

    public func credentials() async throws -> [Credential] { try await get("/api/credentials") }

    public func reveal(_ id: String, field: SecretField) async throws -> String {
        struct Body: Encodable { let field: String }
        struct Value: Decodable { let value: String }
        let v: Value = try await post("/api/credentials/\(escape(id))/reveal", Body(field: field.rawValue))
        return v.value
    }

    public func totp(_ id: String) async throws -> TOTPCode { try await get("/api/credentials/\(escape(id))/totp") }

    public func audit(limit: Int = 200) async throws -> [AuditEvent] {
        try await get("/api/audit", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    /// Met à jour le favori d'une entrée (PUT complet, comme le fait Relay web).
    public func setFavorite(_ entry: Entry, _ favorite: Bool) async throws -> Entry {
        struct Input: Encodable {
            let folderId: String?
            let name: String
            let kind: String
            let host: String
            let port: Int
            let url: String
            let username: String
            let credentialId: String?
            let settings: [String: String]
            let notes: String
            let favorite: Bool
        }
        // Les réglages avancés ne sont pas modélisés côté mobile : on relit la fiche complète pour les conserver.
        let raw: [String: JSONValue] = try await get("/api/entries/\(escape(entry.id))")
        var object = raw
        object["favorite"] = .bool(favorite)
        for key in ["id", "createdAt", "updatedAt", "sourceId", "externalId"] { object.removeValue(forKey: key) }
        let body = try JSONEncoder().encode(object)
        return try decode(await send(request("PUT", "/api/entries/\(escape(entry.id))", body: body)))
    }

    /// URL WebSocket du tunnel Guacamole pour un jeton de session.
    nonisolated public func tunnelURL(token: String) -> URL? {
        guard var components = URLComponents(url: account.server, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        components.path = "/api/tunnel"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    nonisolated private func escape(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    }
}

/// Valeur JSON générique (relecture d'une fiche sans en modéliser tous les champs).
public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

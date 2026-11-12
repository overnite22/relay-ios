import XCTest
@testable import RelayKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Transport synthétique : enregistre les requêtes et renvoie des réponses préparées.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    struct Response { let status: Int; let body: String }
    var responses: [String: Response] = [:]
    var requests: [URLRequest] = []
    let lock = NSLock()

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
        let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
        guard let r = responses[key] else { throw URLError(.cannotFindHost) }
        let http = HTTPURLResponse(url: request.url!, statusCode: r.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        return (Data(r.body.utf8), http)
    }
}

final class RelayClientTests: XCTestCase {
    let account = ServerAccount(server: URL(string: "https://relay.example.com")!, token: "rlt_" + String(repeating: "b", count: 43))

    func testRequestsCarryTokenAndCSRFHeader() async throws {
        let stub = StubTransport()
        stub.responses["GET /api/me"] = .init(status: 200, body: #"{"user":"moi@example.com","version":"0.6"}"#)
        let client = RelayClient(account: account, transport: stub)
        let me = try await client.me()
        XCTAssertEqual(me, ServerInfo(user: "moi@example.com", version: "0.6"))
        let req = stub.requests[0]
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer \(account.token)")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-Relay"), "1")
        XCTAssertEqual(req.url?.absoluteString, "https://relay.example.com/api/me")
    }

    func testTreeDecodingWithUnknownKindAndSearch() async throws {
        let stub = StubTransport()
        stub.responses["GET /api/tree"] = .init(status: 200, body: """
        {"folders":[{"id":"f1","parentId":null,"name":"Lab","createdAt":"2026-11-11T10:00:00Z","updatedAt":"2026-11-11T10:00:00Z"},
                    {"id":"f2","parentId":"f1","name":"Proxmox","createdAt":"","updatedAt":""}],
         "entries":[{"id":"e1","folderId":"f2","name":"pve1","kind":"ssh","host":"pve1.lab.example","port":22,"url":"","username":"root",
                     "credentialId":"c1","settings":{"sftp":true},"notes":"Nœud 1","favorite":true,"sourceId":null,"externalId":"","createdAt":"","updatedAt":"2026-11-11T10:00:00.5Z"},
                    {"id":"e2","folderId":null,"name":"Futur","kind":"telnet","host":"x","port":23,"url":"","username":"","credentialId":null,
                     "settings":{},"notes":"","favorite":false,"sourceId":null,"externalId":"","createdAt":"","updatedAt":""}]}
        """)
        let client = RelayClient(account: account, transport: stub)
        let tree = try await client.tree()
        XCTAssertEqual(tree.entries.count, 2)
        XCTAssertEqual(tree.entries[1].kind, .other)
        XCTAssertEqual(tree.entries[0].target, "pve1.lab.example:22")
        XCTAssertEqual(tree.path(of: "f2").map(\.name), ["Lab", "Proxmox"])
        XCTAssertEqual(tree.search("pve nœud").map(\.id), ["e1"])
        XCTAssertEqual(tree.entries(in: nil).map(\.id), ["e2"])
        XCTAssertNotNil(RelayDate.parse(tree.entries[0].updatedAt))
    }

    func testErrorsAreMapped() async throws {
        let stub = StubTransport()
        stub.responses["GET /api/tree"] = .init(status: 401, body: #"{"error":"Authentification requise"}"#)
        stub.responses["GET /api/credentials"] = .init(status: 500, body: #"{"error":"erreur interne"}"#)
        stub.responses["POST /api/entries/e1/connect"] = .init(status: 403, body: #"{"error":"origine refusée"}"#)
        let client = RelayClient(account: account, transport: stub)
        do { _ = try await client.tree(); XCTFail() } catch { XCTAssertEqual(error as? RelayError, .unauthorized) }
        do { _ = try await client.credentials(); XCTFail() } catch { XCTAssertEqual(error as? RelayError, .server("erreur interne")) }
        do { _ = try await client.connect("e1", options: SessionOptions(width: 1, height: 1)); XCTFail() } catch { XCTAssertEqual(error as? RelayError, .forbidden("origine refusée")) }
        do { _ = try await client.audit(); XCTFail() } catch {
            if case .transport = error as? RelayError {} else { XCTFail("\(error)") }
        }
    }

    func testConnectBodyAndTunnelURL() async throws {
        let stub = StubTransport()
        stub.responses["POST /api/entries/e%201/connect"] = .init(status: 200, body: #"{"token":"abc","protocol":"rdp"}"#)
        let client = RelayClient(account: account, transport: stub)
        let ticket = try await client.connect("e 1", options: SessionOptions(width: 1200, height: 800, dpi: 192, timezone: "Europe/Paris", record: false))
        XCTAssertEqual(ticket, SessionTicket(token: "abc", protocol: "rdp"))
        let body = try XCTUnwrap(stub.requests[0].httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["width", "height", "dpi", "timezone", "record"])
        XCTAssertEqual(json["dpi"] as? Int, 192)
        XCTAssertEqual(client.tunnelURL(token: "a b")?.absoluteString, "wss://relay.example.com/api/tunnel?token=a%20b")
    }

    func testRevealAndTotp() async throws {
        let stub = StubTransport()
        stub.responses["POST /api/credentials/c1/reveal"] = .init(status: 200, body: #"{"value":"s3cret"}"#)
        stub.responses["GET /api/credentials/c1/totp"] = .init(status: 200, body: #"{"code":"123456","remaining":12,"period":30}"#)
        let client = RelayClient(account: account, transport: stub)
        let value = try await client.reveal("c1", field: .password)
        XCTAssertEqual(value, "s3cret")
        XCTAssertEqual(String(data: stub.requests[0].httpBody ?? Data(), encoding: .utf8), #"{"field":"password"}"#)
        let totp = try await client.totp("c1")
        XCTAssertEqual(totp, TOTPCode(code: "123456", remaining: 12, period: 30))
    }

    func testQuickConnectEncodesAllServerFields() throws {
        let req = QuickConnectRequest(kind: .ssh, host: "h", port: 22, username: "u", options: SessionOptions(width: 10, height: 20, dpi: 96, timezone: "UTC"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(req)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["kind", "host", "port", "username", "domain", "password", "width", "height", "dpi", "timezone", "record"])
        XCTAssertEqual(json["kind"] as? String, "ssh")
    }
}

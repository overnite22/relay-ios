import XCTest
@testable import RelayKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class ManagementTests: XCTestCase {
    private func client(_ stub: StubTransport) -> RelayClient {
        RelayClient(account: ServerAccount(server: URL(string: "https://relay.example.com")!, token: "rlt_x"), transport: stub)
    }

    private func json(_ request: URLRequest?) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request?.httpBody ?? Data()) as? [String: Any]) ?? [:]
    }

    func testEntryRoundTripKeepsAdvancedSettings() async throws {
        let stub = StubTransport()
        let entry = #"{"id":"e1","folderId":"f1","name":"srv","kind":"rdp","host":"192.0.2.20","port":3389,"url":"","username":"","credentialId":null,"settings":{"security":"nla","ignoreCert":true,"resize":"display-update"},"notes":"n","favorite":false,"sourceId":null,"externalId":"","createdAt":"","updatedAt":""}"#
        stub.responses["GET /api/entries/e1"] = .init(status: 200, body: entry)
        stub.responses["PUT /api/entries/e1"] = .init(status: 200, body: entry)
        stub.responses["POST /api/entries"] = .init(status: 201, body: entry)
        stub.responses["DELETE /api/entries/e1"] = .init(status: 204, body: "")
        let c = client(stub)
        var input = try await c.entryInput("e1")
        XCTAssertEqual(input.settings["ignoreCert"], .bool(true))
        input.name = "srv-renommé"
        _ = try await c.saveEntry(input, id: "e1")
        let body = json(stub.requests.last)
        XCTAssertEqual(Set(body.keys), ["folderId", "name", "kind", "host", "port", "url", "username", "credentialId", "settings", "notes", "favorite"])
        XCTAssertEqual((body["settings"] as? [String: Any])?["security"] as? String, "nla")
        XCTAssertTrue(body["credentialId"] is NSNull)
        _ = try await c.saveEntry(EntryInput(folderId: nil, name: "neuf", kind: .ssh, host: "h", port: 22))
        XCTAssertEqual(stub.requests.last?.httpMethod, "POST")
        try await c.deleteEntry("e1")
    }

    func testFoldersAndInheritedCredentials() async throws {
        let stub = StubTransport()
        stub.responses["POST /api/folders"] = .init(status: 201, body: #"{"id":"f2","parentId":null,"name":"Neuf","credentials":{}}"#)
        stub.responses["PUT /api/folders/f2"] = .init(status: 200, body: #"{"id":"f2","parentId":"f1","name":"Renommé"}"#)
        stub.responses["PUT /api/folders/f2/credentials"] = .init(status: 204, body: "")
        stub.responses["DELETE /api/folders/f2"] = .init(status: 204, body: "")
        let c = client(stub)
        _ = try await c.saveFolder(name: "Neuf", parentId: nil)
        XCTAssertTrue(json(stub.requests.last)["parentId"] is NSNull)
        let moved = try await c.saveFolder(name: "Renommé", parentId: "f1", id: "f2")
        XCTAssertEqual(moved.parentId, "f1")
        try await c.setFolderCredentials("f2", ["ssh": "c1", "rdp": nil])
        let creds = json(stub.requests.last)["credentials"] as? [String: Any]
        XCTAssertEqual(creds?["ssh"] as? String, "c1")
        XCTAssertTrue(creds?["rdp"] is NSNull)
        try await c.deleteFolder("f2")
    }

    func testCredentialSecretsAreOnlySentWhenChanged() async throws {
        let stub = StubTransport()
        let cred = #"{"id":"c1","name":"Admin","username":"root","domain":"","notes":"","hasPassword":true,"hasPrivateKey":false,"hasPassphrase":false,"hasTotp":false}"#
        stub.responses["PUT /api/credentials/c1"] = .init(status: 200, body: cred)
        stub.responses["POST /api/credentials"] = .init(status: 201, body: cred)
        let c = client(stub)
        _ = try await c.saveCredential(CredentialInput(name: "Admin", username: "root"), id: "c1")
        XCTAssertEqual(Set(json(stub.requests.last).keys), ["name", "username", "domain", "notes"])
        _ = try await c.saveCredential(CredentialInput(name: "Admin", username: "root", password: "x", totp: ""))
        XCTAssertEqual(json(stub.requests.last)["totp"] as? String, "")
    }

    func testAttachmentsSourcesDuplicatesImportBackup() async throws {
        let stub = StubTransport()
        stub.responses["GET /api/entries/e1/attachments"] = .init(status: 200, body: #"[{"id":"a1","name":"schéma.pdf","size":10,"createdAt":"2026-11-12T10:00:00Z"}]"#)
        stub.responses["POST /api/entries/e1/attachments"] = .init(status: 201, body: #"{"id":"a2","name":"x.txt","size":1,"createdAt":"2026-11-12T10:00:00Z"}"#)
        stub.responses["GET /api/entries/e1/attachments/a1"] = .init(status: 200, body: "PDF")
        stub.responses["GET /api/sources"] = .init(status: 200, body: #"[{"id":"s1","kind":"proxmox","name":"Cluster","url":"https://pve.example.com:8006","tokenId":"relay@pve!relay","hasSecret":true,"verifyTls":false,"folderId":"f","options":{"guestEntries":true},"intervalMin":15,"lastSyncAt":null,"lastStatus":"OK","createdAt":"","updatedAt":""}]"#)
        stub.responses["POST /api/sources/s1/sync"] = .init(status: 200, body: #"{"ok":true,"message":"12 entrées"}"#)
        stub.responses["PUT /api/sources/s1"] = .init(status: 200, body: stub.responses["GET /api/sources"]!.body.dropFirst().dropLast().description)
        stub.responses["GET /api/duplicates"] = .init(status: 200, body: #"[{"key":"ssh|192.0.2.1|22","label":"192.0.2.1:22","entries":[]}]"#)
        stub.responses["POST /api/entries/e1/merge"] = .init(status: 200, body: #"{"id":"e1","folderId":null,"name":"srv","kind":"ssh","host":"h","port":22,"url":"","username":"","credentialId":null,"notes":"","favorite":false,"sourceId":null,"updatedAt":""}"#)
        stub.responses["POST /api/import/rdm/preview"] = .init(status: 200, body: #"{"folders":[{"path":["A"]}],"entries":[{"name":"x","kind":"ssh","host":"h","port":22,"url":"","username":"","path":["A"],"credential":"","inlineSecret":false,"rdmType":"SSHShell"}],"credentials":[],"skipped":[{"name":"VBR","type":"Extension","reason":"non pris en charge"}],"warnings":[]}"#)
        stub.responses["POST /api/import/rdm/apply"] = .init(status: 200, body: #"{"folders":1,"entries":1,"credentials":0,"rootId":"r"}"#)
        stub.responses["POST /api/backups/export"] = .init(status: 200, body: "RELAYBACKUP")
        stub.responses["POST /api/backups/restore"] = .init(status: 200, body: #"{"ok":true}"#)
        let c = client(stub)
        let files = try await c.attachments("e1")
        XCTAssertEqual(files.first?.name, "schéma.pdf")
        _ = try await c.addAttachment("e1", name: "x.txt", data: Data("x".utf8))
        XCTAssertEqual(stub.requests.last?.url?.query, "name=x.txt")
        XCTAssertEqual(stub.requests.last?.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
        let content = try await c.attachmentData("e1", id: "a1")
        XCTAssertEqual(content, Data("PDF".utf8))
        let sources = try await c.sources()
        XCTAssertEqual(sources.first?.kindTitle, "Proxmox VE")
        let sync = try await c.syncSource("s1")
        XCTAssertTrue(sync.ok)
        var input = SyncSourceInput(sources[0])
        input.intervalMin = 30
        _ = try await c.saveSource(input, id: "s1")
        XCTAssertNil(json(stub.requests.last)["secret"], "secret inchangé non envoyé")
        let groups = try await c.duplicates()
        XCTAssertEqual(groups.first?.label, "192.0.2.1:22")
        _ = try await c.merge(keep: "e1", remove: ["e2"])
        let plan = try await c.previewImport(Data("<xml/>".utf8))
        XCTAssertEqual(plan.skipped.first?.name, "VBR")
        let result = try await c.applyImport(Data("<xml/>".utf8), folder: "Import RDM", sshDefault: "c1", rdpDefault: "")
        XCTAssertEqual(result.entries, 1)
        XCTAssertTrue(stub.requests.last?.url?.query?.contains("sshDefault=c1") ?? false)
        let archive = try await c.exportBackup(password: "secret")
        XCTAssertEqual(archive, Data("RELAYBACKUP".utf8))
        try await c.restoreBackup(archive, password: "pässe")
        XCTAssertEqual(stub.requests.last?.value(forHTTPHeaderField: "X-Backup-Password"), Data("pässe".utf8).base64EncodedString())
    }
}

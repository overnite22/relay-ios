import XCTest
@testable import RelayKit

final class CommandsTests: XCTestCase {
    func testRunLifecycle() async throws {
        let stub = StubTransport()
        let running = #"{"id":"r1","at":"2026-11-12T10:00:00Z","finishedAt":null,"user":"a@example.com","command":"uptime","sudo":false,"targets":2,"ok":0,"failed":0,"results":[{"entryId":"e1","name":"pve-01","address":"192.0.2.10:22","status":"running","exitCode":null,"output":"","truncated":false,"error":"","durationMs":0,"fingerprint":"","newHostKey":false},{"entryId":"e2","name":"pve-02","address":"192.0.2.12:22","status":"futur","exitCode":null,"output":"","truncated":false,"error":"","durationMs":0,"fingerprint":"","newHostKey":false}]}"#
        stub.responses["POST /api/commands/run"] = .init(status: 200, body: running)
        stub.responses["GET /api/commands/runs/r1"] = .init(status: 200, body: running.replacingOccurrences(of: #""finishedAt":null"#, with: #""finishedAt":"2026-11-12T10:00:02Z""#))
        stub.responses["POST /api/commands/runs/r1/cancel"] = .init(status: 204, body: "")
        stub.responses["GET /api/commands/runs"] = .init(status: 200, body: "[]")
        stub.responses["GET /api/commands/saved"] = .init(status: 200, body: #"[{"id":"s1","name":"Disque","command":"df -h","sudo":false}]"#)
        stub.responses["POST /api/commands/saved"] = .init(status: 200, body: #"{"id":"s2","name":"Maj","command":"apt update","sudo":true}"#)
        stub.responses["PUT /api/commands/saved/s1"] = .init(status: 200, body: #"{"id":"s1","name":"Disque","command":"df -hT","sudo":false}"#)
        stub.responses["DELETE /api/commands/saved/s1"] = .init(status: 204, body: "")
        stub.responses["POST /api/known-hosts/forget"] = .init(status: 204, body: "")
        let client = RelayClient(account: ServerAccount(server: URL(string: "https://relay.example.com")!, token: "rlt_x"), transport: stub)

        let run = try await client.startRun(RunRequest(entryIds: ["e1", "e2"], command: "uptime", sudo: false))
        XCTAssertFalse(run.finished)
        XCTAssertEqual(run.results?.map(\.status), [.running, .unknown])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: stub.requests[0].httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["entryIds", "command", "sudo", "timeoutSec", "concurrency"])
        let done = try await client.run("r1")
        XCTAssertTrue(done.finished)
        try await client.cancelRun("r1")
        _ = try await client.runHistory()
        XCTAssertEqual(stub.requests.last?.url?.query, "limit=50")
        let saved = try await client.savedCommands()
        XCTAssertEqual(saved.first?.command, "df -h")
        let created = try await client.saveCommand(SavedCommand(name: "Maj", command: "apt update", sudo: true))
        XCTAssertEqual(created.id, "s2")
        let updated = try await client.saveCommand(SavedCommand(id: "s1", name: "Disque", command: "df -hT", sudo: false))
        XCTAssertEqual(updated.command, "df -hT")
        try await client.deleteSavedCommand("s1")
        try await client.forgetHostKey(address: "192.0.2.10:22")
        XCTAssertEqual(String(data: stub.requests.last?.httpBody ?? Data(), encoding: .utf8), #"{"address":"192.0.2.10:22"}"#)
    }
}

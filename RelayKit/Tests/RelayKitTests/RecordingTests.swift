import XCTest
@testable import RelayKit

final class RecordingTests: XCTestCase {
    private func i(_ op: String, _ args: String...) -> String { GuacInstruction(op, args).encoded() }

    func testTimelineSplitsFramesAndAssemblesImages() throws {
        let blob = Data("png".utf8).base64EncodedString()
        var text = i("size", "0", "800", "600") + i("rect", "0", "0", "0", "10", "10") + i("cfill", "14", "0", "1", "2", "3", "255")
        text += i("sync", "100000")
        text += i("img", "3", "14", "0", "image/png", "5", "6") + i("blob", "3", blob) + i("end", "3") + i("sync", "100250")
        text += i("copy", "0", "0", "0", "5", "5", "14", "0", "1", "1") + i("sync", "160250")
        text += i("rect", "0", "1", "1", "1", "1")
        let t = try RecordingTimeline.decode(Data(text.utf8))
        XCTAssertEqual(t.frames.map(\.time), [0, 250, 60250, 60250])
        XCTAssertEqual(t.frames[0].commands.count, 3)
        XCTAssertEqual(t.frames[1].commands, [.image(layer: 0, mask: 14, x: 5, y: 6, mime: "image/png", data: Data("png".utf8))])
        XCTAssertEqual(t.duration, 60250)
        XCTAssertEqual(t.frameIndex(at: 0), 0)
        XCTAssertEqual(t.frameIndex(at: 300), 1)
        XCTAssertEqual(t.frameIndex(at: 999_999), 3)
        XCTAssertEqual(t.delay(before: 2, speed: 1, skipIdle: false), 60, accuracy: 0.001)
        XCTAssertEqual(t.delay(before: 2, speed: 1, skipIdle: true), 1, accuracy: 0.001)
        XCTAssertEqual(t.delay(before: 1, speed: 2, skipIdle: true), 0.125, accuracy: 0.001)
        XCTAssertEqual(RecordingTimeline.clock(60250), "1:00")
        XCTAssertEqual(RecordingTimeline.clock(3_725_000), "1:02:05")
    }

    func testDecodeSpansChunkBoundaries() throws {
        // Une image de plus d'un mégaoctet traverse plusieurs morceaux de lecture.
        let payload = Data(repeating: 7, count: 900_000).base64EncodedString()
        let text = i("img", "1", "12", "0", "image/png", "0", "0") + i("blob", "1", payload) + i("end", "1") + i("sync", "5")
        let t = try RecordingTimeline.decode(Data(text.utf8))
        XCTAssertEqual(t.frames.count, 1)
        if case .image(_, _, _, _, _, let data) = t.frames[0].commands.first { XCTAssertEqual(data.count, 900_000) } else { XCTFail() }
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try RecordingTimeline.decode(Data("abc;def".utf8)))
    }

    func testClientListsAndDownloads() async throws {
        let stub = StubTransport()
        stub.responses["GET /api/recordings"] = .init(status: 200, body: """
        [{"id":"a","name":"pve-01","kind":"ssh","at":"2026-11-10T10:00:00Z","size":10,"limited":false},
         {"id":"b","name":"srv","kind":"rdp","at":"2026-11-12T10:00:00Z","size":20,"limited":true}]
        """)
        stub.responses["GET /api/recordings/b"] = .init(status: 200, body: "4.sync,1.1;")
        stub.responses["DELETE /api/recordings/a"] = .init(status: 204, body: "")
        let client = RelayClient(account: ServerAccount(server: URL(string: "https://relay.example.com")!, token: "rlt_x"), transport: stub)
        let list = try await client.recordings()
        XCTAssertEqual(list.map(\.id), ["b", "a"])
        XCTAssertEqual(list[0].kind, .rdp)
        let data = try await client.recordingData("b")
        XCTAssertEqual(String(data: data, encoding: .utf8), "4.sync,1.1;")
        try await client.deleteRecording("a")
        XCTAssertEqual(stub.requests.last?.httpMethod, "DELETE")
    }
}

import XCTest
@testable import RelayKit

final class ClientCoreTests: XCTestCase {
    private func make() -> (GuacClientCore, Box) {
        let core = GuacClientCore()
        let box = Box()
        core.onSend = { box.sent.append($0) }
        core.onDisplay = { box.display.append($0) }
        core.onState = { box.states.append($0) }
        core.onError = { box.errors.append($0) }
        core.onClipboard = { box.clipboard.append($0) }
        return (core, box)
    }

    final class Box {
        var sent: [String] = []
        var display: [DisplayCommand] = []
        var states: [GuacState] = []
        var errors: [GuacError] = []
        var clipboard: [String] = []
    }

    func testHandshakeStatesAndSync() {
        let (core, box) = make()
        core.connecting()
        core.receive("0.,8.tunnel-1;")
        XCTAssertEqual(core.state, .waiting)
        XCTAssertEqual(core.tunnelID, "tunnel-1")
        core.receive("4.size,1.0,3.800,3.600;4.sync,2.17;")
        XCTAssertEqual(core.state, .connected)
        XCTAssertEqual(box.display, [.size(layer: 0, width: 800, height: 600), .sync(timestamp: 17)])
        core.acknowledgeSync(17)
        XCTAssertEqual(box.sent.last, "4.sync,2.17;")
        XCTAssertEqual(box.states, [.connecting, .waiting, .connected])
    }

    func testImageStreamIsAssembledAndAcked() {
        let (core, box) = make()
        core.connecting()
        core.receive("0.,1.t;4.sync,1.0;")
        let part1 = Data("hello ".utf8).base64EncodedString()
        let part2 = Data("world".utf8).base64EncodedString()
        core.receive("3.img,1.3,2.14,1.0,9.image/png,2.10,2.20;4.blob,1.3,\(part1.unicodeScalars.count).\(part1);")
        core.receive("4.blob,1.3,\(part2.unicodeScalars.count).\(part2);3.end,1.3;")
        XCTAssertEqual(box.display.last, .image(layer: 0, mask: 14, x: 10, y: 20, mime: "image/png", data: Data("hello world".utf8)))
        XCTAssertEqual(box.sent.filter { $0.hasPrefix("3.ack") }.count, 2)
        XCTAssertEqual(box.sent.last, "3.ack,1.3,2.OK,1.0;")
    }

    func testClipboardFromServer() {
        let (core, box) = make()
        core.connecting()
        core.receive("0.,1.t;4.sync,1.0;")
        let text = Data("bonjour".utf8).base64EncodedString()
        core.receive("9.clipboard,1.5,10.text/plain;4.blob,1.5,\(text.unicodeScalars.count).\(text);3.end,1.5;")
        XCTAssertEqual(box.clipboard, ["bonjour"])
    }

    func testErrorAndDisconnect() {
        let (core, box) = make()
        core.connecting()
        core.receive("0.,11.relay-error;5.error,14.Jeton invalide,3.769;")
        XCTAssertEqual(box.errors, [GuacError(message: "Jeton invalide", status: 769)])
        XCTAssertEqual(core.state, .disconnected)
        XCTAssertTrue(box.errors[0].description.contains("Non autorisé"))
    }

    func testInputsOnlyWhenConnected() {
        let (core, box) = make()
        core.sendMouse(x: 1, y: 2, buttons: .left)
        XCTAssertTrue(box.sent.isEmpty)
        core.connecting()
        core.receive("0.,1.t;4.sync,1.0;")
        core.sendMouse(x: 1, y: 2, buttons: [.left])
        core.tapKey(Keysym.enter)
        core.type("é")
        core.sendClipboard("abc")
        XCTAssertEqual(box.sent.filter { !$0.hasPrefix("4.sync") }, [
            "5.mouse,1.1,1.2,1.1;", "3.key,5.65293,1.1;", "3.key,5.65293,1.0;", "3.key,3.233,1.1;", "3.key,3.233,1.0;",
            "9.clipboard,1.0,10.text/plain;", "4.blob,1.0,4.YWJj;", "3.end,1.0;",
        ])
        core.disconnect()
        XCTAssertEqual(box.sent.last, "10.disconnect;")
        XCTAssertEqual(core.state, .disconnected)
    }

    func testUnsupportedStreamsAreRefused() {
        let (core, box) = make()
        core.connecting()
        core.receive("0.,1.t;4.sync,1.0;5.audio,1.2,9.audio/l16;4.file,1.4,10.text/plain,5.a.txt;")
        XCTAssertEqual(box.sent.filter { $0.contains("Unsupported") }.count, 2)
    }

    func testDrawingInstructions() {
        let (core, box) = make()
        core.connecting()
        core.receive("0.,1.t;4.sync,1.0;")
        core.receive("4.rect,1.0,1.1,1.2,2.30,2.40;5.cfill,2.14,1.0,3.255,1.0,1.0,3.255;4.copy,2.-1,1.0,1.0,2.10,2.10,2.14,1.0,1.5,1.6;6.cursor,1.1,1.2,2.-2,1.0,1.0,2.16,2.16;7.dispose,2.-1;")
        XCTAssertEqual(Array(box.display.dropFirst()), [
            .rect(layer: 0, x: 1, y: 2, width: 30, height: 40),
            .cfill(layer: 0, mask: 14, r: 255, g: 0, b: 0, a: 255),
            .copy(src: -1, sx: 0, sy: 0, width: 10, height: 10, mask: 14, dst: 0, dx: 5, dy: 6),
            .cursor(hotX: 1, hotY: 2, src: -2, sx: 0, sy: 0, width: 16, height: 16),
            .dispose(layer: -1),
        ])
    }
}

final class ScriptedTransportTests: XCTestCase {
    func testReplaysScriptAndRecordsSends() {
        let transport = ScriptedTransport(script: ["0.,1.t;", "4.sync,1.5;"])
        let done = expectation(description: "script")
        let received = LockedBox()
        transport.onText = { text in
            received.append(text)
            if text.hasPrefix("4.sync") { done.fulfill() }
        }
        transport.start()
        wait(for: [done], timeout: 2)
        XCTAssertEqual(received.items, ["0.,1.t;", "4.sync,1.5;"])
        transport.send("3.nop;")
        XCTAssertEqual(transport.sent, ["3.nop;"])
    }
}

final class LockedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func append(_ s: String) { lock.lock(); storage.append(s); lock.unlock() }
    var items: [String] { lock.lock(); defer { lock.unlock() }; return storage }
}

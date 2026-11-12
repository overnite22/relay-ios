import XCTest
@testable import RelayKit

final class FilesTests: XCTestCase {
    private func connected() -> (GuacClientCore, ClientCoreTests.Box) {
        let core = GuacClientCore()
        let box = ClientCoreTests.Box()
        core.onSend = { box.sent.append($0) }
        core.connecting()
        core.receive("0.,1.t;4.sync,1.0;")
        box.sent.removeAll()
        return (core, box)
    }

    private func i(_ op: String, _ args: String...) -> String { GuacInstruction(op, args).encoded() }

    func testListingDirectory() throws {
        let (core, box) = connected()
        var fsObject = -1
        core.onFilesystem = { index, _ in fsObject = index }
        core.receive(i("filesystem", "0", "SFTP"))
        XCTAssertEqual(fsObject, 0)
        var result: GuacClientCore.ObjectResult?
        core.requestObject(0, name: "/home") { result = $0 }
        XCTAssertEqual(box.sent.last, "3.get,1.0,5./home;")
        let json = #"{"/home/b.txt":"text/plain","/home/a":"application/vnd.glyptodon.guacamole.stream-index+json","/home/A10.log":"text/plain","/home/a2.log":"text/plain"}"#
        let b64 = Data(json.utf8).base64EncodedString()
        core.receive(i("body", "0", "7", GuacClientCore.directoryMimetype, "/home"))
        XCTAssertEqual(box.sent.last, "3.ack,1.7,2.OK,1.0;")
        core.receive(i("blob", "7", b64) + i("end", "7"))
        guard case .success(let value)? = result else { return XCTFail("pas de réponse") }
        XCTAssertEqual(value.mimetype, GuacClientCore.directoryMimetype)
        let items = try RemoteItem.parseIndex(value.data)
        XCTAssertEqual(items.map(\.name), ["a", "a2.log", "A10.log", "b.txt"])
        XCTAssertTrue(items[0].isDirectory)
    }

    func testUploadWaitsForEachAck() {
        let (core, box) = connected()
        let data = Data(repeating: 1, count: GuacClientCore.blobSize + 10)
        var progress: [Int] = []
        var done: Result<Void, GuacError>?
        core.putObject(0, name: "/tmp/x.bin", mimetype: "application/octet-stream", data: data, progress: { progress.append($0) }) { done = $0 }
        XCTAssertEqual(box.sent, ["3.put,1.0,1.0,24.application/octet-stream,10./tmp/x.bin;"])
        core.receive(i("ack", "0", "OK", "0"))
        XCTAssertTrue(box.sent.last?.hasPrefix("4.blob,1.0,") ?? false)
        XCTAssertEqual(box.sent.count, 2)
        core.receive(i("ack", "0", "OK", "0"))
        XCTAssertEqual(box.sent.count, 3)
        core.receive(i("ack", "0", "OK", "0"))
        XCTAssertEqual(box.sent.last, "3.end,1.0;")
        XCTAssertEqual(progress, [GuacClientCore.blobSize, GuacClientCore.blobSize + 10])
        if case .success? = done {} else { XCTFail("envoi non terminé") }
    }

    func testUploadRefused() {
        let (core, _) = connected()
        var done: Result<Void, GuacError>?
        core.putObject(0, name: "/root/x", mimetype: "text/plain", data: Data("x".utf8)) { done = $0 }
        core.receive(i("ack", "0", "Permission denied", "771"))
        if case .failure(let e)? = done { XCTAssertEqual(e.message, "Permission denied") } else { XCTFail() }
    }

    func testServerPushedFileAndDisconnectFailsTransfers() {
        let (core, box) = connected()
        var received: GuacClientCore.ReceivedFile?
        core.onFileReceived = { received = $0 }
        let b64 = Data("bonjour".utf8).base64EncodedString()
        core.receive(i("file", "4", "text/plain", "rapport.txt") + i("blob", "4", b64) + i("end", "4"))
        XCTAssertEqual(received, GuacClientCore.ReceivedFile(name: "rapport.txt", mimetype: "text/plain", data: Data("bonjour".utf8)))
        XCTAssertTrue(box.sent.contains("3.ack,1.4,2.OK,1.0;"))
        var pending: GuacClientCore.ObjectResult?
        core.requestObject(0, name: "/") { pending = $0 }
        core.tunnelClosed()
        if case .failure? = pending {} else { XCTFail("requête non abandonnée") }
    }

    func testPaths() {
        XCTAssertEqual(RemotePath.parent("/home/user/"), "/home")
        XCTAssertEqual(RemotePath.parent("/home"), "/")
        XCTAssertEqual(RemotePath.parent("/"), "/")
        XCTAssertEqual(RemotePath.join("/", "a"), "/a")
        XCTAssertEqual(RemotePath.join("/home", "a"), "/home/a")
        XCTAssertEqual(RemotePath.basename("/home/a.txt"), "a.txt")
    }
}

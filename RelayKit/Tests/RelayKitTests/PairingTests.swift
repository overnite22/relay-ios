import XCTest
@testable import RelayKit

final class PairingTests: XCTestCase {
    let token = "rlt_" + String(repeating: "a", count: 43)

    func testParsesQRCode() throws {
        let account = try Pairing.parse(code: "relay://pair?server=https%3A%2F%2Frelay.example.com&token=\(token)")
        XCTAssertEqual(account.server.absoluteString, "https://relay.example.com")
        XCTAssertEqual(account.token, token)
        XCTAssertEqual(account.serverDisplay, "relay.example.com")
    }

    func testRejectsForeignCodes() {
        XCTAssertThrowsError(try Pairing.parse(code: "https://example.com/x")) { XCTAssertEqual($0 as? PairingError, .notPairingCode) }
        XCTAssertThrowsError(try Pairing.parse(code: "relay://pair?server=https://a.example&token=abc")) { XCTAssertEqual($0 as? PairingError, .invalidToken) }
        XCTAssertThrowsError(try Pairing.parse(code: "relay://pair?server=http://a.example&token=\(token)")) { XCTAssertEqual($0 as? PairingError, .insecureServer) }
    }

    func testManualServerNormalisation() throws {
        XCTAssertEqual(try Pairing.serverURL("relay.example.com").absoluteString, "https://relay.example.com")
        XCTAssertEqual(try Pairing.serverURL("https://relay.example.com/some/path?x=1").absoluteString, "https://relay.example.com")
        XCTAssertEqual(try Pairing.serverURL("http://localhost:8080").absoluteString, "http://localhost:8080")
        XCTAssertThrowsError(try Pairing.serverURL("http://relay.example.com"))
        XCTAssertThrowsError(try Pairing.serverURL("https://user:pw@relay.example.com"))
        XCTAssertThrowsError(try Pairing.serverURL(""))
        XCTAssertThrowsError(try Pairing.account(server: "https://a.example", token: "rlt_short"))
    }
}

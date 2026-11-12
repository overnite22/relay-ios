import XCTest
@testable import RelayKit

final class InstructionTests: XCTestCase {
    func testEncodeCountsUnicodeScalars() {
        let i = GuacInstruction("key", "233", "1")
        XCTAssertEqual(i.encoded(), "3.key,3.233,1.1;")
        XCTAssertEqual(GuacInstruction("name", "é€😀").encoded(), "4.name,3.é€😀;")
        XCTAssertEqual(GuacInstruction("", "ping", "12").encoded(), "0.,4.ping,2.12;")
    }

    func testParseSeveralInstructionsAndFragments() throws {
        var parser = GuacParser()
        var out = try parser.feed("4.size,1.0,4.1280,3.720;4.sync,2.")
        XCTAssertEqual(out, [GuacInstruction("size", "0", "1280", "720")])
        out = try parser.feed("42;3.nop;")
        XCTAssertEqual(out, [GuacInstruction("sync", "42"), GuacInstruction("nop")])
        out = try parser.feed("4.name,3.é€😀")
        XCTAssertEqual(out, [])
        out = try parser.feed(";")
        XCTAssertEqual(out, [GuacInstruction("name", "é€😀")])
    }

    func testParseRejectsMalformedInput() {
        var parser = GuacParser()
        XCTAssertThrowsError(try parser.feed("abc;"))
        var other = GuacParser()
        XCTAssertThrowsError(try other.feed("3.nop:"))
    }

    func testAccessors() {
        let i = GuacInstruction("arc", "0", "10", "20", "5", "1.5", "3", "1")
        XCTAssertEqual(i.int(1), 10)
        XCTAssertEqual(i.double(4), 1.5)
        XCTAssertEqual(i.int(99), 0)
        XCTAssertEqual(i.string(0), "0")
    }
}

final class KeysymTests: XCTestCase {
    func testLatinAndUnicode() {
        XCTAssertEqual(Keysym.from(scalar: "a"), 0x61)
        XCTAssertEqual(Keysym.from(scalar: "é"), 0xE9)
        XCTAssertEqual(Keysym.from(scalar: "€"), 0x0100_20AC)
        XCTAssertEqual(Keysym.from(scalar: "\n"), Keysym.enter)
        XCTAssertEqual(Keysym.sequence(for: "ls\n"), [0x6C, 0x73, Keysym.enter])
        XCTAssertEqual(Keysym.function(12), 0xFFC9)
        XCTAssertEqual(Keysym.function(1), 0xFFBE)
    }
}

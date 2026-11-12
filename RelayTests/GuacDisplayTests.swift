import CoreGraphics
import RelayKit
import XCTest
@testable import Relay

/// Vérifie le rendu CoreGraphics pixel par pixel (orientation, copies, images, calques).
final class GuacDisplayTests: XCTestCase {
    /// Couleur RGBA d'un pixel, origine en haut à gauche.
    private func pixel(_ image: CGImage?, _ x: Int, _ y: Int, file: StaticString = #filePath, line: UInt = #line) -> [UInt8] {
        guard let image else {
            XCTFail("image absente", file: file, line: line)
            return []
        }
        var data = [UInt8](repeating: 0, count: 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else {
            XCTFail("contexte", file: file, line: line)
            return []
        }
        // Le pixel (x, y) haut-gauche est placé à l'origine du contexte 1×1.
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return data
    }

    private func close(_ a: [UInt8], _ b: [UInt8], tolerance: Int = 3) -> Bool {
        guard a.count == 4, b.count == 4 else { return false }
        return zip(a, b).allSatisfy { abs(Int($0) - Int($1)) <= tolerance }
    }

    func testFillIsTopLeftOriented() {
        let d = GuacDisplay()
        d.apply(.size(layer: 0, width: 100, height: 50))
        d.apply(.rect(layer: 0, x: 0, y: 0, width: 10, height: 5))
        d.apply(.cfill(layer: 0, mask: 14, r: 255, g: 0, b: 0, a: 255))
        let img = d.composite()
        XCTAssertEqual(img?.width, 100)
        XCTAssertEqual(img?.height, 50)
        XCTAssertTrue(close(pixel(img, 2, 2), [255, 0, 0, 255]), "\(pixel(img, 2, 2))")
        XCTAssertTrue(close(pixel(img, 2, 45), [0, 0, 0, 0]), "le bas doit rester vide")
    }

    func testCopyAndResizeKeepContent() {
        let d = GuacDisplay()
        d.apply(.size(layer: 0, width: 40, height: 40))
        d.apply(.rect(layer: 0, x: 0, y: 0, width: 4, height: 4))
        d.apply(.cfill(layer: 0, mask: 14, r: 0, g: 255, b: 0, a: 255))
        d.apply(.copy(src: 0, sx: 0, sy: 0, width: 4, height: 4, mask: 14, dst: 0, dx: 30, dy: 20))
        d.apply(.size(layer: 0, width: 60, height: 60))
        let img = d.composite()
        XCTAssertTrue(close(pixel(img, 31, 21), [0, 255, 0, 255]))
        XCTAssertTrue(close(pixel(img, 1, 1), [0, 255, 0, 255]))
        XCTAssertTrue(close(pixel(img, 31, 30), [0, 0, 0, 0]))
    }

    func testPNGImageAndBufferCursor() throws {
        let d = GuacDisplay()
        d.apply(.size(layer: 0, width: 200, height: 100))
        let data = try XCTUnwrap(Data(base64Encoded: GuacFixture.png))
        d.apply(.image(layer: 0, mask: 14, x: 10, y: 20, mime: "image/png", data: data))
        let img = d.composite()
        // Damier de 8 px : premier carré bleu Relay, le suivant blanc.
        XCTAssertTrue(close(pixel(img, 12, 22), [43, 125, 233, 255]), "\(pixel(img, 12, 22))")
        XCTAssertTrue(close(pixel(img, 20, 22), [255, 255, 255, 255]), "\(pixel(img, 20, 22))")

        d.apply(.size(layer: -1, width: 8, height: 8))
        d.apply(.rect(layer: -1, x: 0, y: 0, width: 8, height: 8))
        d.apply(.cfill(layer: -1, mask: 14, r: 255, g: 255, b: 0, a: 255))
        XCTAssertTrue(d.apply(.cursor(hotX: 1, hotY: 1, src: -1, sx: 0, sy: 0, width: 8, height: 8)))
        XCTAssertEqual(d.cursorImage?.width, 8)
        // Les tampons (< 0) ne sont jamais composés à l'écran.
        XCTAssertTrue(close(pixel(d.composite(), 2, 2), [0, 0, 0, 0]))
    }

    func testVisibleLayerIsComposited() {
        let d = GuacDisplay()
        d.apply(.size(layer: 0, width: 50, height: 50))
        d.apply(.size(layer: 2, width: 10, height: 10))
        d.apply(.rect(layer: 2, x: 0, y: 0, width: 10, height: 10))
        d.apply(.cfill(layer: 2, mask: 14, r: 0, g: 0, b: 255, a: 255))
        d.apply(.move(layer: 2, parent: 0, x: 30, y: 5, z: 1))
        let img = d.composite()
        XCTAssertTrue(close(pixel(img, 32, 7), [0, 0, 255, 255]))
        XCTAssertTrue(close(pixel(img, 5, 7), [0, 0, 0, 0]))
        d.apply(.dispose(layer: 2))
        XCTAssertTrue(close(pixel(d.composite(), 32, 7), [0, 0, 0, 0]))
    }

    func testClipAndPushPop() {
        let d = GuacDisplay()
        d.apply(.size(layer: 0, width: 20, height: 20))
        d.apply(.push(layer: 0))
        d.apply(.rect(layer: 0, x: 0, y: 0, width: 5, height: 20))
        d.apply(.clip(layer: 0))
        d.apply(.rect(layer: 0, x: 0, y: 0, width: 20, height: 20))
        d.apply(.cfill(layer: 0, mask: 14, r: 255, g: 255, b: 255, a: 255))
        d.apply(.pop(layer: 0))
        var img = d.composite()
        XCTAssertTrue(close(pixel(img, 2, 10), [255, 255, 255, 255]))
        XCTAssertTrue(close(pixel(img, 10, 10), [0, 0, 0, 0]))
        d.apply(.rect(layer: 0, x: 10, y: 10, width: 2, height: 2))
        d.apply(.cfill(layer: 0, mask: 14, r: 255, g: 0, b: 0, a: 255))
        img = d.composite()
        XCTAssertTrue(close(pixel(img, 10, 10), [255, 0, 0, 255]), "le clip doit être levé après pop")
    }

    @MainActor func testFixtureScriptRendersThroughEngine() async {
        let transport = ScriptedTransport(script: GuacFixture.script)
        let engine = GuacEngine(transport: transport)
        let rendered = expectation(description: "trame")
        nonisolated(unsafe) var frame: GuacEngine.Frame?
        engine.onFrame = { f in
            frame = f
            rendered.fulfill()
        }
        engine.start()
        await fulfillment(of: [rendered], timeout: 5)
        XCTAssertEqual(frame?.size, CGSize(width: 1170, height: 1800))
        XCTAssertTrue(close(pixel(frame?.image, 5, 5), [43, 125, 233, 255]))
        XCTAssertTrue(close(pixel(frame?.image, 202, 1252), [43, 125, 233, 255]), "copie de l'image")
        engine.stop()
    }
}

final class SessionPreferencesTests: XCTestCase {
    func testSSHUsesNativePixelsAndScaledDPI() {
        UserDefaults.standard.removeObject(forKey: SessionPreferences.sshTextKey)
        let o = SessionPreferences.options(kind: .ssh, viewSize: CGSize(width: 390, height: 700), displayScale: 3, record: true)
        XCTAssertEqual(o.width, 1170)
        XCTAssertEqual(o.height, 2100)
        XCTAssertEqual(o.dpi, 245)
        XCTAssertTrue(o.record)
    }

    func testRDPUsesResolutionSetting() {
        UserDefaults.standard.set(2.0, forKey: SessionPreferences.rdpResolutionKey)
        defer { UserDefaults.standard.removeObject(forKey: SessionPreferences.rdpResolutionKey) }
        let o = SessionPreferences.options(kind: .rdp, viewSize: CGSize(width: 844, height: 390), displayScale: 3, record: false)
        XCTAssertEqual(o.width, 1688)
        XCTAssertEqual(o.height, 780)
        XCTAssertEqual(o.dpi, 96)
    }
}

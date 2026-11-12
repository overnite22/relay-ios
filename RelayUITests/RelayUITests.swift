import XCTest

/// Parcours des écrans avec le faux serveur ; chaque étape laisse une capture dans le .xcresult.
final class RelayUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPairingScreen() {
        let app = launch(["--ui-testing-unpaired"])
        XCTAssertTrue(app.staticTexts["Relay"].waitForExistence(timeout: 10))
        app.buttons["pairManual"].tap()
        let server = app.textFields["pairServer"]
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        server.tap()
        server.typeText("http://relay.example.com")
        let token = app.secureTextFields["pairToken"]
        token.tap()
        token.typeText("rlt_" + String(repeating: "y", count: 43))
        app.buttons["pairConnect"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'HTTPS'")).firstMatch.waitForExistence(timeout: 5))
        shot(app, "01-appairage")
    }

    func testBrowseEntryVaultAndTools() {
        let app = launch(["--ui-testing"])
        XCTAssertTrue(app.staticTexts["Favoris"].waitForExistence(timeout: 10))
        shot(app, "02-connexions")

        app.buttons["folder-Laboratoire"].tap()
        app.buttons["folder-Proxmox"].tap()
        XCTAssertTrue(app.buttons["entry-pve-02"].waitForExistence(timeout: 5))
        shot(app, "03-dossier")
        app.buttons["entry-pve-01"].tap()
        XCTAssertTrue(app.buttons["entryOpen"].waitForExistence(timeout: 5))
        app.buttons["entryTest"].tap()
        XCTAssertTrue(app.staticTexts["Port accessible"].waitForExistence(timeout: 5))
        shot(app, "04-fiche")

        app.tabBars.buttons["Disponibilité"].tap()
        XCTAssertTrue(app.buttons["entry-pve-02"].waitForExistence(timeout: 5))
        shot(app, "05-disponibilite")

        app.tabBars.buttons["Coffre"].tap()
        app.buttons["credential-Console fournisseur"].tap()
        app.buttons["credentialReveal"].tap()
        XCTAssertTrue(app.staticTexts["Exemple-Secret-42"].waitForExistence(timeout: 5))
        app.buttons["credentialShowTotp"].tap()
        XCTAssertTrue(app.staticTexts["492 039"].waitForExistence(timeout: 5))
        shot(app, "06-coffre")

        app.tabBars.buttons["Plus"].tap()
        app.buttons["moreQuick"].tap()
        XCTAssertTrue(app.buttons["quickConnect"].waitForExistence(timeout: 5))
        shot(app, "07-connexion-rapide")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["moreAudit"].tap()
        XCTAssertTrue(app.staticTexts["Appareil appairé"].waitForExistence(timeout: 5))
        shot(app, "08-journal")
    }

    func testScriptedSession() {
        let app = launch(["--ui-testing"])
        XCTAssertTrue(app.staticTexts["Favoris"].waitForExistence(timeout: 10))
        app.buttons["entry-pve-01"].firstMatch.tap()
        app.buttons["entryOpen"].tap()
        XCTAssertTrue(app.navigationBars["pve-01 (démo)"].waitForExistence(timeout: 10))
        shot(app, "09-session")
        app.buttons["sessionKeyboard"].tap()
        XCTAssertTrue(app.buttons["keyCtrl"].waitForExistence(timeout: 5))
        app.buttons["keyCtrl"].tap()
        shot(app, "10-session-clavier")
        app.buttons["keyHide"].tap()
        app.buttons["sessionClose"].tap()
        XCTAssertTrue(app.buttons["entryOpen"].waitForExistence(timeout: 5))
    }
}

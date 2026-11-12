import XCTest

/// Parcours des écrans avec le faux serveur ; chaque étape laisse une capture dans le .xcresult.
final class RelayUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private var current: XCUIApplication?

    /// Capture automatique à chaque échec, pour diagnostiquer depuis les artefacts de la CI.
    override func record(_ issue: XCTIssue) {
        var issue = issue
        if let app = current {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "echec-" + name.replacingOccurrences(of: " ", with: "_")
            attachment.lifetime = .keepAlways
            issue.add(attachment)
        }
        super.record(issue)
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        current = app
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
        let password = app.staticTexts["credentialPassword"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        XCTAssertTrue(NSPredicate(format: "label CONTAINS %@", "Exemple-Secret-42").evaluate(with: password) || password.label.contains("Exemple"),
                      "mot de passe non affiché : \(password.label)")
        app.buttons["credentialShowTotp"].tap()
        XCTAssertTrue(app.staticTexts["credentialTotp"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.descendants(matching: .any)["remoteScreen"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["pve-01 (démo)"].waitForExistence(timeout: 10))
        shot(app, "09-session")
        app.buttons["sessionKeyboard"].tap()
        XCTAssertTrue(app.buttons["keyCtrl"].waitForExistence(timeout: 5))
        app.buttons["keyCtrl"].tap()
        shot(app, "10-session-clavier")
        app.buttons["keyHide"].tap()
        app.buttons["sessionClose"].tap()
        XCTAssertTrue(app.buttons["entryOpen"].waitForExistence(timeout: 5))
    }

    func testRecordingPlayback() {
        let app = launch(["--ui-testing"])
        XCTAssertTrue(app.staticTexts["Favoris"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Plus"].tap()
        app.buttons["moreRecordings"].tap()
        XCTAssertTrue(app.buttons["recording-pve-01"].waitForExistence(timeout: 5))
        shot(app, "11-enregistrements")
        app.buttons["recording-pve-01"].tap()
        let toggle = app.buttons["playerToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        // Pauses sautées : la fin (60 s) est atteinte en quelques secondes.
        let ended = NSPredicate(format: "label == %@", "Lecture")
        expectation(for: ended, evaluatedWith: toggle)
        waitForExpectations(timeout: 20)
        XCTAssertEqual(app.staticTexts["playerPosition"].label, "0:59")
        shot(app, "12-lecture")
        toggle.tap()
        XCTAssertTrue(app.buttons["playerClose"].waitForExistence(timeout: 5))
        app.buttons["playerClose"].tap()
        XCTAssertTrue(app.buttons["recording-pve-01"].waitForExistence(timeout: 5))
    }

    func testProxmoxConsoleAndSeveralSessions() {
        let app = launch(["--ui-testing"])
        XCTAssertTrue(app.staticTexts["Favoris"].waitForExistence(timeout: 10))
        // Console Proxmox : même rendu que les autres sessions.
        app.buttons["folder-Laboratoire"].tap()
        app.buttons["folder-Proxmox"].tap()
        app.buttons["entry-vm-101 (console)"].tap()
        XCTAssertTrue(app.buttons["entryOpen"].waitForExistence(timeout: 5))
        app.buttons["entryOpen"].tap()
        XCTAssertTrue(app.staticTexts["pve-01 (démo)"].waitForExistence(timeout: 10))
        shot(app, "13-console-proxmox")
        // Réduire puis ouvrir une deuxième session : les deux restent ouvertes.
        app.buttons["sessionMinimize"].tap()
        XCTAssertTrue(app.buttons["sessionsPill"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["entry-pve-02"].tap()
        app.buttons["entryOpen"].tap()
        let switcher = app.buttons["sessionSwitcher"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 10))
        switcher.tap()
        XCTAssertTrue(app.buttons["vm-101 (console)"].waitForExistence(timeout: 5) || app.buttons["pve-01 (démo)"].waitForExistence(timeout: 2))
        shot(app, "14-sessions")
        app.buttons["Réduire toutes les sessions"].tap()
        XCTAssertTrue(app.buttons["sessionsPill"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sessionsPill"].label.contains("2 sessions"))
    }

    func testWorkspaceOpensAllSessions() {
        let app = launch(["--ui-testing"])
        XCTAssertTrue(app.staticTexts["Favoris"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Plus"].tap()
        app.buttons["moreWorkspaces"].tap()
        let workspace = app.buttons["workspace-Tour du matin"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 5))
        shot(app, "15-espaces")
        workspace.tap()
        XCTAssertTrue(app.buttons["sessionSwitcher"].waitForExistence(timeout: 10))
        app.buttons["sessionMinimize"].firstMatch.tap()
        XCTAssertTrue(app.buttons["sessionsPill"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sessionsPill"].label.contains("2 sessions"))
    }

    func testSessionFiles() {
        let app = launch(["--ui-testing"])
        XCTAssertTrue(app.staticTexts["Favoris"].waitForExistence(timeout: 10))
        app.buttons["entry-pve-01"].firstMatch.tap()
        app.buttons["entryOpen"].tap()
        let files = app.buttons["sessionFiles"]
        XCTAssertTrue(files.waitForExistence(timeout: 10))
        files.tap()
        XCTAssertTrue(app.buttons["file-rapport.txt"].waitForExistence(timeout: 5))
        app.buttons["file-Documents"].tap()
        XCTAssertTrue(app.buttons["file-notes.md"].waitForExistence(timeout: 5))
        shot(app, "16-fichiers")
        app.buttons["file-notes.md"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["transfer-notes.md"].waitForExistence(timeout: 5))
        sleep(2)
        shot(app, "17-fichier-telecharge")
    }

    func testCommandBroadcast() {
        let app = launch(["--ui-testing"])
        XCTAssertTrue(app.staticTexts["Favoris"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Commandes"].tap()
        app.buttons["commandTargets"].tap()
        XCTAssertTrue(app.buttons["targetFolder-Laboratoire"].waitForExistence(timeout: 5))
        app.buttons["targetFolder-Laboratoire"].tap()
        shot(app, "18-commande-cibles")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let editor = app.textViews["commandText"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("uptime")
        app.buttons["commandRun"].tap()
        XCTAssertTrue(app.buttons["result-pve-01"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'réussie'")).firstMatch.waitForExistence(timeout: 10))
        shot(app, "19-commande-resultats")
        app.buttons["result-pve-01"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'load average'")).firstMatch.waitForExistence(timeout: 5))
        shot(app, "20-commande-sortie")
    }

    func testEditingAndAdministration() {
        let app = launch(["--ui-testing"])
        XCTAssertTrue(app.staticTexts["Favoris"].waitForExistence(timeout: 10))
        // Nouvelle entrée depuis la racine.
        app.buttons["addMenu"].tap()
        app.buttons["addEntry"].tap()
        let name = app.textFields["editorName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("nouveau")
        app.textFields["editorHost"].tap()
        app.textFields["editorHost"].typeText("192.0.2.50")
        shot(app, "21-nouvelle-entree")
        app.buttons["editorSave"].tap()
        XCTAssertTrue(app.staticTexts["Favoris"].waitForExistence(timeout: 5))
        // Modifier une entrée existante : fiche relue, pièces jointes visibles.
        app.buttons["entry-pve-01"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["schema-reseau.pdf"].waitForExistence(timeout: 5))
        app.buttons["entryEdit"].tap()
        XCTAssertTrue(app.buttons["editorDelete"].waitForExistence(timeout: 5))
        shot(app, "22-modifier-entree")
        app.buttons["Annuler"].tap()
        // Coffre : nouvel identifiant.
        app.tabBars.buttons["Coffre"].tap()
        app.buttons["credNew"].tap()
        XCTAssertTrue(app.textFields["credName"].waitForExistence(timeout: 5))
        shot(app, "23-nouvel-identifiant")
        app.buttons["Annuler"].tap()
        // Administration.
        app.tabBars.buttons["Plus"].tap()
        app.buttons["moreSources"].tap()
        XCTAssertTrue(app.buttons["source-Cluster labo"].waitForExistence(timeout: 5))
        app.buttons["source-Cluster labo"].tap()
        app.buttons["sourceSync"].tap()
        XCTAssertTrue(app.staticTexts["Connexion réussie : Proxmox VE 9.2"].waitForExistence(timeout: 5))
        shot(app, "24-source")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["moreDuplicates"].tap()
        XCTAssertTrue(app.staticTexts["ancien-pve-02"].waitForExistence(timeout: 5))
        shot(app, "25-doublons")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["moreBackup"].tap()
        shot(app, "26-sauvegarde")
    }
}

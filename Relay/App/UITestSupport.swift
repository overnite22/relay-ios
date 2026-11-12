#if DEBUG
import Foundation
import RelayKit

/// Données fictives pour les tests UI (aucun serveur réel, aucun secret réel).
/// Lancement : --ui-testing (appairé) ou --ui-testing-unpaired.
@MainActor enum UITestSupport {
    static func session() -> AppSession? {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui-testing-unpaired") {
            return AppSession(store: MemoryAccountStore(), transport: FixtureHTTP())
        }
        guard args.contains("--ui-testing") else { return nil }
        UserDefaults.standard.set(["e-pve1", "e-win"], forKey: "recentEntryIds")
        UserDefaults.standard.set(false, forKey: Biometrics.settingKey)
        let account = ServerAccount(server: URL(string: "https://relay.example.com")!, token: "rlt_" + String(repeating: "x", count: 43))
        let app = AppSession(store: MemoryAccountStore(account), transport: FixtureHTTP())
        app.tunnelOverride = { _ in ScriptedTransport(script: GuacFixture.script) }
        return app
    }
}

/// Faux serveur Relay.
final class FixtureHTTP: HTTPTransport, @unchecked Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await Task.sleep(for: .milliseconds(150))
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        let body: String
        var status = 200
        switch (method, path) {
        case ("GET", "/api/me"): body = #"{"user":"admin@example.com","version":"0.7.0"}"#
        case ("GET", "/api/tree"): body = Self.tree
        case ("GET", "/api/connection-status"): body = Self.status
        case ("GET", "/api/credentials"): body = Self.credentials
        case ("GET", "/api/audit"): body = Self.audit
        case ("GET", "/api/workspaces"): body = #"[{"id":"w-matin","name":"Tour du matin","entryIds":["e-pve1","e-win"]}]"#
        case ("POST", "/api/workspaces"), ("PUT", "/api/workspaces/w-matin"):
            body = String(data: request.httpBody ?? Data(), encoding: .utf8)?
                .replacingOccurrences(of: #""id":"""#, with: #""id":"w-new""#) ?? "{}"
        case ("DELETE", "/api/workspaces/w-matin"):
            let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (Data(), response)
        case ("GET", "/api/recordings"): body = Self.recordings
        case ("GET", "/api/recordings/r-demo"): body = GuacFixture.recording
        case ("DELETE", let p) where p.hasPrefix("/api/recordings/"):
            let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (Data(), response)
        case ("POST", let p) where p.hasSuffix("/reveal"): body = #"{"value":"Exemple-Secret-42"}"#
        case ("GET", let p) where p.hasSuffix("/totp"): body = #"{"code":"492039","remaining":21,"period":30}"#
        case ("POST", let p) where p.hasSuffix("/test-connection"):
            body = #"{"address":"192.0.2.10:22","ip":"192.0.2.10","status":"reachable","durationMs":4,"checkedAt":"2026-11-12T08:00:00Z"}"#
        case ("POST", "/api/quick-connect"):
            body = #"{"token":"fixture","protocol":"ssh"}"#
        case ("POST", let p) where p.hasSuffix("/connect"):
            body = #"{"token":"fixture","protocol":"ssh"}"#
        default:
            status = 404
            body = #"{"error":"introuvable"}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(body.utf8), response)
    }

    static let tree = """
    {"folders":[
      {"id":"f-lab","parentId":null,"name":"Laboratoire"},
      {"id":"f-pve","parentId":"f-lab","name":"Proxmox"},
      {"id":"f-win","parentId":null,"name":"Windows"}],
     "entries":[
      {"id":"e-pve1","folderId":"f-pve","name":"pve-01","kind":"ssh","host":"pve-01.lab.example","port":22,"url":"","username":"root","credentialId":"c-key","notes":"Nœud principal.\\n**Maintenance** le mardi.","favorite":true,"sourceId":"s1","updatedAt":"2026-11-12T08:00:00Z"},
      {"id":"e-pve2","folderId":"f-pve","name":"pve-02","kind":"ssh","host":"192.0.2.12","port":22,"url":"","username":"root","credentialId":"c-key","notes":"","favorite":false,"sourceId":"s1","updatedAt":""},
      {"id":"e-console","folderId":"f-pve","name":"vm-101 (console)","kind":"pve","host":"","port":0,"url":"","username":"","credentialId":null,"notes":"","favorite":false,"sourceId":"s1","updatedAt":""},
      {"id":"e-win","folderId":"f-win","name":"srv-ad-01","kind":"rdp","host":"192.0.2.20","port":3389,"url":"","username":"","credentialId":"c-admin","notes":"Contrôleur de domaine.","favorite":true,"sourceId":null,"updatedAt":""},
      {"id":"e-backup","folderId":"f-win","name":"srv-backup","kind":"rdp","host":"192.0.2.21","port":3389,"url":"","username":"","credentialId":"c-admin","notes":"","favorite":false,"sourceId":null,"updatedAt":""},
      {"id":"e-nas","folderId":"f-lab","name":"nas-01","kind":"web","host":"","port":0,"url":"https://nas.lab.example","username":"admin","credentialId":null,"notes":"","favorite":false,"sourceId":null,"updatedAt":""},
      {"id":"e-root","folderId":null,"name":"bastion","kind":"ssh","host":"bastion.example.com","port":2222,"url":"","username":"ops","credentialId":null,"notes":"","favorite":false,"sourceId":null,"updatedAt":""}]}
    """

    static let status = """
    {"e-pve1":{"address":"pve-01.lab.example:22","ip":"192.0.2.10","status":"reachable","durationMs":3,"checkedAt":"2026-11-12T08:00:00Z"},
     "e-pve2":{"address":"192.0.2.12:22","status":"timeout","durationMs":3000,"checkedAt":"2026-11-12T08:00:00Z"},
     "e-win":{"address":"192.0.2.20:3389","status":"reachable","durationMs":5,"checkedAt":"2026-11-12T08:00:00Z"},
     "e-backup":{"address":"192.0.2.21:3389","status":"refused","durationMs":2,"checkedAt":"2026-11-12T08:00:00Z"}}
    """

    static let credentials = """
    [{"id":"c-admin","name":"Administrateur du domaine","username":"Administrator","domain":"LAB","notes":"","hasPassword":true,"hasPrivateKey":false,"hasPassphrase":false,"hasTotp":false},
     {"id":"c-key","name":"Clé SSH personnelle","username":"root","domain":"","notes":"Clé ed25519.","hasPassword":false,"hasPrivateKey":true,"hasPassphrase":true,"hasTotp":false},
     {"id":"c-mfa","name":"Console fournisseur","username":"ops@example.com","domain":"","notes":"","hasPassword":true,"hasPrivateKey":false,"hasPassphrase":false,"hasTotp":true}]
    """

    static let recordings = """
    [{"id":"r-demo","name":"pve-01","kind":"ssh","at":"2026-11-12T07:30:00Z","size":48213,"limited":false},
     {"id":"r-old","name":"srv-ad-01","kind":"rdp","at":"2026-11-10T16:05:00Z","size":67108864,"limited":true}]
    """

    static let audit = """
    [{"id":3,"at":"2026-11-12T07:58:00Z","user":"admin@example.com","action":"session.open","target":"pve-01","detail":"ssh"},
     {"id":2,"at":"2026-11-12T07:40:00Z","user":"admin@example.com","action":"device.create","target":"d1","detail":"iPhone"},
     {"id":1,"at":"2026-11-11T18:00:00Z","user":"admin@example.com","action":"source.sync","target":"Proxmox","detail":"12 entrées"}]
    """
}

/// Session Guacamole scriptée : fond, cadres, texte simulé et image PNG (vérifie le rendu de bout en bout).
enum GuacFixture {
    static let png = "iVBORw0KGgoAAAANSUhEUgAAAGAAAABACAYAAADlNHIOAAAA0klEQVR4nO3XsQ0CQRAEwc+HGAmYKCADMDD69FMnndnSSGXt9Xi+3t/+r6f/r7/qAes9AADbPQAA2z0AANv9dfrAu/cA4h5A3AOIewBxDyDuAcQ9gLh3iMU9AADbPQAA2z0AANs9gBrg9IF37wHEPYC4BxD3AOIeQNwDiHsAce8Qi3sAALZ7AAC2ewAAtnsANcDpA+/eA4h7AHEPIO4BxD2AuAcQ9wDi3iEW9wAAbPcAAGz3AABs9wBqgNMH3r0HEPcA4h5A3AOIewBxDyDuAcT9B4SClJNl9ZprAAAAAElFTkSuQmCC"

    /// Enregistrement : la trame de démonstration, un carré qui traverse l'écran, puis une longue pause.
    static var recording: String {
        func i(_ op: String, _ args: String...) -> String { GuacInstruction(op, args).encoded() }
        var text = script.dropFirst().joined().replacingOccurrences(of: i("sync", "1"), with: i("sync", "1000"))
        for step in 0..<30 {
            let x = 40 + step * 35
            text += i("rect", "0", String(x - 35), "1000", "60", "60") + i("cfill", "14", "0", "18", "20", "24", "255")
            text += i("rect", "0", String(x), "1000", "60", "60") + i("cfill", "14", "0", "229", "112", "0", "255")
            text += i("sync", String(1100 + step * 100))
        }
        text += i("rect", "0", "40", "1100", "400", "40") + i("cfill", "14", "0", "63", "185", "80", "255") + i("sync", "60000")
        return text
    }

    static var script: [String] {
        func i(_ op: String, _ args: String...) -> String { GuacInstruction(op, args).encoded() }
        var out: [String] = [i("", "fixture-tunnel")]
        var frame = i("size", "0", "1170", "1800")
        frame += i("rect", "0", "0", "0", "1170", "1800") + i("cfill", "14", "0", "18", "20", "24", "255")
        frame += i("rect", "0", "0", "0", "1170", "70") + i("cfill", "14", "0", "43", "125", "233", "255")
        for row in 0..<14 {
            let y = 110 + row * 52
            let width = 200 + (row * 137) % 760
            frame += i("rect", "0", "40", String(y), String(width), "26")
            frame += i("cfill", "14", "0", row % 3 == 0 ? "63" : "200", row % 3 == 0 ? "185" : "200", row % 3 == 0 ? "80" : "205", "255")
        }
        frame += i("start", "0", "900", "1300") + i("line", "0", "1100", "1300") + i("line", "0", "1000", "1450") + i("close", "0")
        frame += i("cfill", "14", "0", "229", "112", "0", "255")
        frame += i("img", "1", "14", "0", "image/png", "60", "1250")
        frame += i("blob", "1", png) + i("end", "1")
        frame += i("copy", "0", "60", "1250", "96", "64", "14", "0", "200", "1250")
        frame += i("size", "-1", "16", "16") + i("rect", "-1", "0", "0", "16", "16") + i("cfill", "14", "-1", "255", "255", "255", "255")
        frame += i("cursor", "0", "0", "-1", "0", "0", "16", "16")
        frame += i("name", "pve-01 (démo)")
        frame += i("sync", "1")
        out.append(frame)
        return out
    }
}
#endif

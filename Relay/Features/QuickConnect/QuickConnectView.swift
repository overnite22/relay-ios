import RelayKit
import SwiftUI

/// Connexion rapide : SSH ou RDP vers une adresse, sans créer de fiche.
struct QuickConnectView: View {
    let app: AppSession
    @AppStorage("quickKind") private var kindRaw = EntryKind.ssh.rawValue
    @AppStorage("quickHost") private var host = ""
    @State private var port = ""
    @State private var credentialId = ""
    @State private var username = ""
    @State private var domain = ""
    @State private var password = ""
    @State private var record = false

    private var kind: EntryKind { EntryKind(rawValue: kindRaw) == .rdp ? .rdp : .ssh }
    private var defaultPort: Int { kind == .rdp ? 3389 : 22 }

    var body: some View {
        Form {
            Section {
                Picker("Protocole", selection: $kindRaw) {
                    Text("SSH").tag(EntryKind.ssh.rawValue)
                    Text("RDP").tag(EntryKind.rdp.rawValue)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("quickKind")
                TextField("Hôte ou adresse IP", text: $host)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .accessibilityIdentifier("quickHost")
                TextField("Port (\(defaultPort))", text: $port).keyboardType(.numberPad)
                    .accessibilityIdentifier("quickPort")
            }
            Section("Authentification") {
                Picker("Identifiant du coffre", selection: $credentialId) {
                    Text("Saisie ponctuelle").tag("")
                    ForEach(app.credentials) { c in Text(c.name).tag(c.id) }
                }
                .accessibilityIdentifier("quickCredential")
                if credentialId.isEmpty {
                    TextField("Utilisateur", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                    if kind == .rdp {
                        TextField("Domaine (facultatif)", text: $domain)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    SecureField("Mot de passe", text: $password).textContentType(.password)
                }
            }
            Section {
                Toggle("Enregistrer la session", isOn: $record)
            } footer: {
                Text("Le mot de passe saisi ici sert uniquement à cette connexion : il n'est ni mémorisé ni ajouté au coffre.")
            }
            Section {
                Button {
                    connect()
                } label: {
                    Label("Connecter", systemImage: "bolt.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty || portValue == nil)
                .accessibilityIdentifier("quickConnect")
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .navigationTitle("Connexion rapide")
        .task { if app.credentials.isEmpty { await app.loadCredentials() } }
    }

    private var portValue: Int? {
        let p = port.trimmingCharacters(in: .whitespaces)
        if p.isEmpty { return defaultPort }
        guard let n = Int(p), (1...65535).contains(n) else { return nil }
        return n
    }

    private func connect() {
        guard let port = portValue else { return }
        let h = host.trimmingCharacters(in: .whitespaces)
        let request = QuickConnectRequest(kind: kind, host: h, port: port,
                                          username: credentialId.isEmpty ? username : "",
                                          domain: credentialId.isEmpty ? domain : "",
                                          password: credentialId.isEmpty ? password : "",
                                          credentialId: credentialId.isEmpty ? nil : credentialId,
                                          options: SessionOptions(width: 1280, height: 720, record: record))
        password = ""
        app.open(.quick(request, title: "\(kind.title) \(h)"))
    }
}

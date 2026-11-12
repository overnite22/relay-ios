import RelayKit
import SwiftUI

/// Onglet « Plus » : outils, réglages et appairage.
struct MoreView: View {
    let app: AppSession
    @AppStorage(SessionPreferences.sshTextKey) private var sshText = 0.85
    @AppStorage(SessionPreferences.rdpResolutionKey) private var rdpResolution = 1.5
    @AppStorage(Biometrics.settingKey) private var requireBiometrics = true
    @State private var confirmUnpair = false
    @State private var showHelp = false

    var body: some View {
        List {
            Section("Outils") {
                NavigationLink {
                    QuickConnectView(app: app)
                } label: {
                    Label("Connexion rapide", systemImage: "bolt.fill")
                }
                .accessibilityIdentifier("moreQuick")
                NavigationLink {
                    AuditView(app: app)
                } label: {
                    Label("Journal d'activité", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("moreAudit")
                NavigationLink {
                    RecordingsView(app: app)
                } label: {
                    Label("Enregistrements", systemImage: "film")
                }
                .accessibilityIdentifier("moreRecordings")
            }
            Section {
                Picker("Texte SSH", selection: $sshText) {
                    Text("Petit").tag(0.7)
                    Text("Normal").tag(0.85)
                    Text("Grand").tag(1.0)
                }
                Picker("Résolution RDP", selection: $rdpResolution) {
                    Text("Écran ×1").tag(1.0)
                    Text("Écran ×1,5").tag(1.5)
                    Text("Écran ×2").tag(2.0)
                }
                Button("Aide des gestes", systemImage: "hand.tap") { showHelp = true }
            } header: {
                Text("Sessions")
            } footer: {
                Text("S'applique aux prochaines connexions. Une résolution plus élevée affiche plus de choses, en plus petit : pincez pour zoomer.")
            }
            Section {
                Toggle("Face ID pour les secrets", isOn: $requireBiometrics)
            } header: {
                Text("Sécurité")
            } footer: {
                Text("Demandé avant d'afficher ou de copier un mot de passe, une clé ou un code TOTP, puis valable une minute.")
            }
            Section("Serveur") {
                LabeledContent("Adresse", value: app.account?.serverDisplay ?? "—")
                LabeledContent("Compte", value: app.info?.user ?? "—")
                LabeledContent("Version de Relay", value: app.info?.version ?? "—")
                LabeledContent("Version de l'app", value: Self.appVersion)
                Button("Désappairer cet iPhone", role: .destructive) { confirmUnpair = true }
                    .accessibilityIdentifier("moreUnpair")
            }
        }
        .navigationTitle("Plus")
        .sheet(isPresented: $showHelp) { GestureHelpView() }
        .confirmationDialog("Désappairer cet iPhone ?", isPresented: $confirmUnpair, titleVisibility: .visible) {
            Button("Désappairer", role: .destructive) { app.unpair() }
        } message: {
            Text("Le jeton est effacé de l'iPhone. Pensez aussi à le révoquer dans Relay web → Administration → Appareils.")
        }
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}

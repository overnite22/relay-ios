import RelayKit
import SwiftUI

/// Premier lancement : appairage par QR code (Relay web → Administration → Appareils) ou saisie manuelle.
struct PairingView: View {
    let app: AppSession
    @State private var scanning = false
    @State private var manual = false
    @State private var server = ""
    @State private var token = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        Image("RelayMark")
                            .resizable().scaledToFit().frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 19))
                            .accessibilityHidden(true)
                        Text("Relay").font(.largeTitle.bold())
                        Text("Vos connexions SSH et RDP, votre coffre et l'état de votre parc, depuis l'iPhone.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section {
                    if scanning {
                        QRScanner { code in
                            scanning = false
                            Task { await pair { try Pairing.parse(code: code) } }
                        }
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .listRowInsets(EdgeInsets())
                        .accessibilityLabel("Lecteur de QR code")
                        Button("Annuler", role: .cancel) { scanning = false }
                    } else {
                        Button {
                            error = nil
                            scanning = true
                        } label: {
                            Label("Scanner le QR code d'appairage", systemImage: "qrcode.viewfinder")
                        }
                        .disabled(!QRScanner.isAvailable || working)
                        .accessibilityIdentifier("pairScan")
                    }
                } header: {
                    Text("Appairer cet iPhone")
                } footer: {
                    Text("Dans Relay web : Administration → Appareils → Appairer. Le QR code n'est affiché qu'une fois.")
                }

                Section {
                    Button {
                        withAnimation { manual.toggle() }
                    } label: {
                        Label("Saisie manuelle", systemImage: manual ? "chevron.down" : "chevron.right")
                    }
                    .accessibilityIdentifier("pairManual")
                    if manual {
                        TextField("https://relay.example.com", text: $server)
                            .textContentType(.URL).keyboardType(.URL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("pairServer")
                        SecureField("Jeton (rlt_…)", text: $token)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("pairToken")
                        Button("Se connecter") {
                            Task { await pair { try Pairing.account(server: server, token: token) } }
                        }
                        .disabled(server.isEmpty || token.isEmpty || working)
                        .accessibilityIdentifier("pairConnect")
                    }
                }

                if working {
                    HStack { ProgressView(); Text("Vérification auprès du serveur…") }
                }
                if let error {
                    StatusBanner(message: error)
                }
            }
            .navigationTitle("Bienvenue")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func pair(_ make: () throws -> ServerAccount) async {
        error = nil
        let account: ServerAccount
        do { account = try make() } catch {
            self.error = error.localizedDescription
            return
        }
        working = true
        defer { working = false }
        do {
            _ = try await app.pair(account)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            self.error = Self.explain(error)
        }
    }

    static func explain(_ error: Error) -> String {
        switch error as? RelayError {
        case .unauthorized:
            return "Le serveur refuse ce jeton. Il a peut-être été révoqué, ou le SSO bloque l'API : ajoutez une exception sur /api/ pour Relay."
        case .invalidResponse:
            return "Réponse inattendue : vérifiez l'adresse, et que le SSO laisse passer /api/ sans redirection."
        default:
            return error.localizedDescription
        }
    }
}

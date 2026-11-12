import RelayKit
import SwiftUI

extension Color {
    /// Bleu Relay (accent de l'interface web).
    static let relayAccent = Color(red: 0.169, green: 0.490, blue: 0.914)
}

extension EntryKind {
    var color: Color {
        switch self {
        case .rdp: return Color(red: 0.16, green: 0.49, blue: 0.91)
        case .ssh: return Color(red: 0.25, green: 0.73, blue: 0.31)
        case .vnc: return Color(red: 0.64, green: 0.44, blue: 0.97)
        case .web: return Color(red: 0.90, green: 0.44, blue: 0.0)
        case .pve: return Color(red: 0.90, green: 0.36, blue: 0.0)
        case .other: return .gray
        }
    }
}

/// Pastille de type (icône sur fond coloré, comme l'arborescence de Relay web).
struct KindBadge: View {
    let kind: EntryKind
    var size: CGFloat = 30
    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(kind.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.24))
            .accessibilityLabel(kind.title)
    }
}

/// Témoin de disponibilité : vert si le port répond, rouge sinon, gris sans mesure.
struct StatusDot: View {
    let test: ConnectionTest?
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(.background, lineWidth: 1))
            .accessibilityLabel(test.map { $0.statusTitle } ?? "Disponibilité inconnue")
    }

    private var color: Color {
        guard let test else { return .gray.opacity(0.5) }
        return test.reachable ? .green : .red
    }
}

/// Message d'erreur ou d'information dans une liste.
struct StatusBanner: View {
    let message: String
    var symbol = "exclamationmark.triangle.fill"
    var tint: Color = .orange
    var body: some View {
        Label { Text(message).font(.callout) } icon: { Image(systemName: symbol).foregroundStyle(tint) }
            .accessibilityIdentifier("statusBanner")
    }
}

/// Bouton de copie avec retour haptique.
struct CopyButton: View {
    let label: String
    let value: () async -> String?
    @State private var copied = false

    var body: some View {
        Button {
            Task {
                guard let v = await value(), !v.isEmpty else { return }
                UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: v]],
                                              options: [.expirationDate: Date().addingTimeInterval(90), .localOnly: true])
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                copied = true
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Copier \(label)")
    }
}

extension String {
    /// Date relative lisible à partir d'une date RFC 3339 du serveur.
    var relativeDate: String {
        guard let date = RelayDate.parse(self) else { return self }
        return date.formatted(.relative(presentation: .named))
    }

    var shortDate: String {
        guard let date = RelayDate.parse(self) else { return self }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

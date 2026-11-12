import Foundation
import RelayKit
import Security

enum KeychainError: Error, LocalizedError {
    case status(OSStatus)
    var errorDescription: String? { "Trousseau indisponible (code \(statusCode))." }
    private var statusCode: Int { if case .status(let s) = self { return Int(s) }; return 0 }
}

/// Persistance du compte (serveur + jeton d'appareil) dans le Keychain, sur cet appareil uniquement.
@MainActor protocol AccountStore {
    func load() throws -> ServerAccount?
    func save(_ account: ServerAccount) throws
    func delete() throws
}

@MainActor final class KeychainAccountStore: AccountStore {
    private let service: String
    init(service: String = "io.github.overnite22.Relay.account") { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "account"]
    }

    func load() throws -> ServerAccount? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(ServerAccount.self, from: data)
    }

    func save(_ account: ServerAccount) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(account),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}

/// Mémoire seule (tests UI et prévisualisation).
@MainActor final class MemoryAccountStore: AccountStore {
    private var account: ServerAccount?
    init(_ account: ServerAccount? = nil) { self.account = account }
    func load() throws -> ServerAccount? { account }
    func save(_ account: ServerAccount) throws { self.account = account }
    func delete() throws { account = nil }
}

import Foundation

/// Fiche complète éditable (réglages avancés conservés tels quels).
public struct EntryInput: Codable, Sendable, Equatable {
    public var folderId: String?
    public var name: String
    public var kind: EntryKind
    public var host: String
    public var port: Int
    public var url: String
    public var username: String
    public var credentialId: String?
    public var settings: [String: JSONValue]
    public var notes: String
    public var favorite: Bool

    enum CodingKeys: String, CodingKey {
        case folderId, name, kind, host, port, url, username, credentialId, settings, notes, favorite
    }

    public init(folderId: String?, name: String = "", kind: EntryKind = .ssh, host: String = "", port: Int = 22, url: String = "",
                username: String = "", credentialId: String? = nil, settings: [String: JSONValue] = [:], notes: String = "", favorite: Bool = false) {
        self.folderId = folderId
        self.name = name
        self.kind = kind
        self.host = host
        self.port = port
        self.url = url
        self.username = username
        self.credentialId = credentialId
        self.settings = settings
        self.notes = notes
        self.favorite = favorite
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        folderId = try c.decodeIfPresent(String.self, forKey: .folderId)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(EntryKind.self, forKey: .kind)
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 0
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        credentialId = try c.decodeIfPresent(String.self, forKey: .credentialId)
        settings = (try? c.decodeIfPresent([String: JSONValue].self, forKey: .settings)) ?? [:]
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(folderId, forKey: .folderId)
        try c.encode(name, forKey: .name)
        try c.encode(kind.rawValue, forKey: .kind)
        try c.encode(host, forKey: .host)
        try c.encode(port, forKey: .port)
        try c.encode(url, forKey: .url)
        try c.encode(username, forKey: .username)
        try c.encode(credentialId, forKey: .credentialId)
        try c.encode(settings, forKey: .settings)
        try c.encode(notes, forKey: .notes)
        try c.encode(favorite, forKey: .favorite)
    }

    /// Port par défaut d'un type.
    public static func defaultPort(_ kind: EntryKind) -> Int {
        switch kind {
        case .ssh: return 22
        case .rdp: return 3389
        case .vnc: return 5900
        default: return 0
        }
    }
}

/// Identifiant du coffre à créer ou modifier. nil = secret inchangé, "" = secret effacé.
public struct CredentialInput: Codable, Sendable, Equatable {
    public var name: String
    public var username: String
    public var domain: String
    public var notes: String
    public var password: String?
    public var privateKey: String?
    public var passphrase: String?
    public var totp: String?

    public init(name: String = "", username: String = "", domain: String = "", notes: String = "",
                password: String? = nil, privateKey: String? = nil, passphrase: String? = nil, totp: String? = nil) {
        self.name = name
        self.username = username
        self.domain = domain
        self.notes = notes
        self.password = password
        self.privateKey = privateKey
        self.passphrase = passphrase
        self.totp = totp
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(username, forKey: .username)
        try c.encode(domain, forKey: .domain)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(password, forKey: .password)
        try c.encodeIfPresent(privateKey, forKey: .privateKey)
        try c.encodeIfPresent(passphrase, forKey: .passphrase)
        try c.encodeIfPresent(totp, forKey: .totp)
    }
}

public struct Attachment: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let size: Int
    public let createdAt: String
}

/// Source de synchronisation (Proxmox ou NetBox).
public struct SyncSource: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let kind: String
    public let name: String
    public let url: String
    public let tokenId: String
    public let hasSecret: Bool
    public let verifyTls: Bool
    public let folderId: String?
    public let options: [String: JSONValue]
    public let intervalMin: Int
    public let lastSyncAt: String?
    public let lastStatus: String

    public var kindTitle: String { kind == "proxmox" ? "Proxmox VE" : (kind == "netbox" ? "NetBox" : kind) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(String.self, forKey: .kind)
        name = try c.decode(String.self, forKey: .name)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        tokenId = try c.decodeIfPresent(String.self, forKey: .tokenId) ?? ""
        hasSecret = try c.decodeIfPresent(Bool.self, forKey: .hasSecret) ?? false
        verifyTls = try c.decodeIfPresent(Bool.self, forKey: .verifyTls) ?? true
        folderId = try c.decodeIfPresent(String.self, forKey: .folderId)
        options = (try? c.decodeIfPresent([String: JSONValue].self, forKey: .options)) ?? [:]
        intervalMin = try c.decodeIfPresent(Int.self, forKey: .intervalMin) ?? 0
        lastSyncAt = try c.decodeIfPresent(String.self, forKey: .lastSyncAt)
        lastStatus = try c.decodeIfPresent(String.self, forKey: .lastStatus) ?? ""
    }
}

public struct SyncSourceInput: Codable, Sendable, Equatable {
    public var kind: String
    public var name: String
    public var url: String
    public var tokenId: String
    public var secret: String?
    public var verifyTls: Bool
    public var options: [String: JSONValue]
    public var intervalMin: Int

    public init(kind: String, name: String = "", url: String = "", tokenId: String = "", secret: String? = nil,
                verifyTls: Bool = true, options: [String: JSONValue] = [:], intervalMin: Int = 0) {
        self.kind = kind
        self.name = name
        self.url = url
        self.tokenId = tokenId
        self.secret = secret
        self.verifyTls = verifyTls
        self.options = options
        self.intervalMin = intervalMin
    }

    public init(_ source: SyncSource) {
        self.init(kind: source.kind, name: source.name, url: source.url, tokenId: source.tokenId, secret: nil,
                  verifyTls: source.verifyTls, options: source.options, intervalMin: source.intervalMin)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(name, forKey: .name)
        try c.encode(url, forKey: .url)
        try c.encode(tokenId, forKey: .tokenId)
        try c.encodeIfPresent(secret, forKey: .secret)
        try c.encode(verifyTls, forKey: .verifyTls)
        try c.encode(options, forKey: .options)
        try c.encode(intervalMin, forKey: .intervalMin)
    }
}

public struct SourceResult: Codable, Sendable, Equatable {
    public let ok: Bool
    public let message: String
}

public struct DuplicateGroup: Codable, Identifiable, Sendable, Hashable {
    public let key: String
    public let label: String
    public let entries: [Entry]
    public var id: String { key }
}

public struct ImportPlan: Codable, Sendable, Equatable {
    public struct PlanFolder: Codable, Sendable, Equatable { public let path: [String] }
    public struct PlanEntry: Codable, Sendable, Equatable {
        public let name: String
        public let kind: EntryKind
        public let host: String
        public let port: Int
        public let path: [String]
        public let credential: String
        public let inlineSecret: Bool
    }
    public struct PlanCredential: Codable, Sendable, Equatable {
        public let name: String
        public let username: String
        public let encryptedSecret: Bool
    }
    public struct Skipped: Codable, Sendable, Equatable {
        public let name: String
        public let type: String
        public let reason: String
    }

    public let folders: [PlanFolder]
    public let entries: [PlanEntry]
    public let credentials: [PlanCredential]
    public let skipped: [Skipped]
    public let warnings: [String]
}

public struct ImportResult: Codable, Sendable, Equatable {
    public let folders: Int
    public let entries: Int
    public let credentials: Int
    public let rootId: String
}

extension RelayClient {
    // MARK: Entrées et dossiers

    /// Fiche complète (avec réglages avancés) pour l'édition.
    public func entryInput(_ id: String) async throws -> EntryInput {
        try await getJSON("/api/entries/\(pathEscape(id))")
    }

    public func saveEntry(_ input: EntryInput, id: String? = nil) async throws -> Entry {
        if let id { return try await putJSON("/api/entries/\(pathEscape(id))", input) }
        return try await postJSON("/api/entries", input)
    }

    public func deleteEntry(_ id: String) async throws {
        try await sendEmpty("DELETE", "/api/entries/\(pathEscape(id))")
    }

    public func saveFolder(name: String, parentId: String?, id: String? = nil) async throws -> Folder {
        struct Body: Encodable {
            let name: String
            let parentId: String?
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(name, forKey: .name)
                try c.encode(parentId, forKey: .parentId)
            }
            enum CodingKeys: String, CodingKey { case name, parentId }
        }
        let body = Body(name: name, parentId: parentId)
        if let id { return try await putJSON("/api/folders/\(pathEscape(id))", body) }
        return try await postJSON("/api/folders", body)
    }

    public func deleteFolder(_ id: String) async throws {
        try await sendEmpty("DELETE", "/api/folders/\(pathEscape(id))")
    }

    /// Identifiants hérités par type d'entrée (nil = aucun).
    public func setFolderCredentials(_ id: String, _ credentials: [String: String?]) async throws {
        struct Body: Encodable { let credentials: [String: String?] }
        try await sendEmpty("PUT", "/api/folders/\(pathEscape(id))/credentials", body: try JSONEncoder().encode(Body(credentials: credentials)))
    }

    // MARK: Coffre

    public func saveCredential(_ input: CredentialInput, id: String? = nil) async throws -> Credential {
        if let id { return try await putJSON("/api/credentials/\(pathEscape(id))", input) }
        return try await postJSON("/api/credentials", input)
    }

    public func deleteCredential(_ id: String) async throws {
        try await sendEmpty("DELETE", "/api/credentials/\(pathEscape(id))")
    }

    // MARK: Pièces jointes

    public func attachments(_ entryId: String) async throws -> [Attachment] {
        try await getJSON("/api/entries/\(pathEscape(entryId))/attachments")
    }

    public func addAttachment(_ entryId: String, name: String, data: Data) async throws -> Attachment {
        try await sendRaw("POST", "/api/entries/\(pathEscape(entryId))/attachments", query: [URLQueryItem(name: "name", value: name)],
                          body: data, contentType: "application/octet-stream")
    }

    public func attachmentData(_ entryId: String, id: String) async throws -> Data {
        try await getRaw("/api/entries/\(pathEscape(entryId))/attachments/\(pathEscape(id))")
    }

    public func deleteAttachment(_ entryId: String, id: String) async throws {
        try await sendEmpty("DELETE", "/api/entries/\(pathEscape(entryId))/attachments/\(pathEscape(id))")
    }

    // MARK: Synchronisation

    public func sources() async throws -> [SyncSource] { try await getJSON("/api/sources") }

    public func saveSource(_ input: SyncSourceInput, id: String? = nil) async throws -> SyncSource {
        if let id { return try await putJSON("/api/sources/\(pathEscape(id))", input) }
        return try await postJSON("/api/sources", input)
    }

    public func deleteSource(_ id: String) async throws {
        try await sendEmpty("DELETE", "/api/sources/\(pathEscape(id))")
    }

    public func testSource(_ id: String) async throws -> SourceResult {
        try await postJSON("/api/sources/\(pathEscape(id))/test", [String: String]())
    }

    public func syncSource(_ id: String) async throws -> SourceResult {
        try await postJSON("/api/sources/\(pathEscape(id))/sync", [String: String]())
    }

    public func clearExclusions(_ sourceId: String) async throws -> String {
        struct Reply: Decodable { let message: String }
        let reply: Reply = try await postJSON("/api/sources/\(pathEscape(sourceId))/clear-exclusions", [String: String]())
        return reply.message
    }

    // MARK: Doublons

    public func duplicates() async throws -> [DuplicateGroup] { try await getJSON("/api/duplicates") }

    public func merge(keep: String, remove ids: [String]) async throws -> Entry {
        struct Body: Encodable { let ids: [String] }
        return try await postJSON("/api/entries/\(pathEscape(keep))/merge", Body(ids: ids))
    }

    // MARK: Import RDM

    public func previewImport(_ file: Data) async throws -> ImportPlan {
        try await sendRaw("POST", "/api/import/rdm/preview", body: file, contentType: "application/xml")
    }

    public func applyImport(_ file: Data, folder: String, sshDefault: String, rdpDefault: String) async throws -> ImportResult {
        try await sendRaw("POST", "/api/import/rdm/apply",
                          query: [URLQueryItem(name: "folder", value: folder), URLQueryItem(name: "sshDefault", value: sshDefault),
                                  URLQueryItem(name: "rdpDefault", value: rdpDefault)],
                          body: file, contentType: "application/xml")
    }

    // MARK: Sauvegarde

    /// Archive chiffrée de toutes les données (à conserver hors du serveur).
    public func exportBackup(password: String) async throws -> Data {
        struct Body: Encodable { let password: String }
        return try await getRaw("/api/backups/export", method: "POST", body: try JSONEncoder().encode(Body(password: password)))
    }

    /// Remplace TOUTES les données du serveur par celles de l'archive.
    public func restoreBackup(_ archive: Data, password: String) async throws {
        struct Empty: Decodable {}
        let encoded = Data(password.utf8).base64EncodedString()
        let _: JSONValue = try await sendRaw("POST", "/api/backups/restore", body: archive, contentType: "application/octet-stream",
                                             extraHeaders: ["X-Backup-Password": encoded])
    }
}

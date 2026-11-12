import Foundation

/// Type d'entrée Relay. Les types inconnus (versions futures du serveur) deviennent `.other`.
public enum EntryKind: String, Codable, Sendable, CaseIterable {
    case rdp, ssh, vnc, web, pve, other

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EntryKind(rawValue: raw) ?? .other
    }

    public var title: String {
        switch self {
        case .rdp: return "RDP"
        case .ssh: return "SSH"
        case .vnc: return "VNC"
        case .web: return "Web"
        case .pve: return "Console Proxmox"
        case .other: return "Autre"
        }
    }

    /// Nom d'icône SF Symbols.
    public var symbol: String {
        switch self {
        case .rdp: return "pc"
        case .ssh: return "terminal"
        case .vnc: return "display"
        case .web: return "globe"
        case .pve: return "server.rack"
        case .other: return "questionmark.square"
        }
    }

    /// Vrai si l'app sait ouvrir une session native (via guacd ; consoles Proxmox relayées par le serveur).
    public var opensNatively: Bool { self == .ssh || self == .rdp || self == .vnc || self == .pve }

    /// Vrai si le serveur surveille la disponibilité de ce type (port TCP).
    public var isMonitored: Bool { self == .ssh || self == .rdp || self == .vnc }

    /// Types qu'on peut créer depuis l'app.
    public static let creatable: [EntryKind] = [.ssh, .rdp, .vnc, .web]
}

public struct Folder: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let parentId: String?
    public let name: String
    /// Identifiant par défaut hérité par les entrées du dossier, par type (« ssh », « rdp »…).
    public let credentials: [String: String?]

    public init(id: String, parentId: String?, name: String, credentials: [String: String?] = [:]) {
        self.id = id
        self.parentId = parentId
        self.name = name
        self.credentials = credentials
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        parentId = try c.decodeIfPresent(String.self, forKey: .parentId)
        name = try c.decode(String.self, forKey: .name)
        credentials = (try? c.decodeIfPresent([String: String?].self, forKey: .credentials)) ?? [:]
    }
}

public struct Entry: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let folderId: String?
    public let name: String
    public let kind: EntryKind
    public let host: String
    public let port: Int
    public let url: String
    public let username: String
    public let credentialId: String?
    public let notes: String
    public let favorite: Bool
    public let sourceId: String?
    public let updatedAt: String

    public init(id: String, folderId: String?, name: String, kind: EntryKind, host: String, port: Int, url: String = "",
                username: String = "", credentialId: String? = nil, notes: String = "", favorite: Bool = false,
                sourceId: String? = nil, updatedAt: String = "") {
        self.id = id
        self.folderId = folderId
        self.name = name
        self.kind = kind
        self.host = host
        self.port = port
        self.url = url
        self.username = username
        self.credentialId = credentialId
        self.notes = notes
        self.favorite = favorite
        self.sourceId = sourceId
        self.updatedAt = updatedAt
    }

    /// Cible affichée : hôte et port (ou URL pour le web).
    public var target: String {
        if kind == .web { return url }
        if host.isEmpty { return "" }
        return port > 0 ? "\(host):\(port)" : host
    }

    /// Texte sur lequel porte la recherche.
    public var searchText: String { [name, host, username, notes].joined(separator: " ").lowercased() }
}

public struct Tree: Codable, Sendable {
    public let folders: [Folder]
    public let entries: [Entry]

    public init(folders: [Folder], entries: [Entry]) {
        self.folders = folders
        self.entries = entries
    }

    public static let empty = Tree(folders: [], entries: [])

    public func folders(in parent: String?) -> [Folder] {
        folders.filter { $0.parentId == parent }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func entries(in folder: String?) -> [Entry] {
        entries.filter { $0.folderId == folder }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func folder(_ id: String?) -> Folder? { id.flatMap { fid in folders.first { $0.id == fid } } }

    public func entry(_ id: String) -> Entry? { entries.first { $0.id == id } }

    /// Chemin d'un dossier (« Racine › Lab › Proxmox »), pour les résultats de recherche.
    public func path(of folderId: String?) -> [Folder] {
        var out: [Folder] = []
        var cursor = folder(folderId)
        var guardCount = 0
        while let f = cursor, guardCount < 64 {
            out.insert(f, at: 0)
            cursor = folder(f.parentId)
            guardCount += 1
        }
        return out
    }

    /// Recherche insensible à la casse sur le nom, l'hôte, l'utilisateur et les notes.
    public func search(_ query: String) -> [Entry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let terms = q.split(separator: " ").map(String.init)
        return entries.filter { e in
            let text = e.searchText
            return terms.allSatisfy { text.contains($0) }
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

public struct Credential: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let username: String
    public let domain: String
    public let notes: String
    public let hasPassword: Bool
    public let hasPrivateKey: Bool
    public let hasPassphrase: Bool
    public let hasTotp: Bool

    public init(id: String, name: String, username: String, domain: String = "", notes: String = "",
                hasPassword: Bool = false, hasPrivateKey: Bool = false, hasPassphrase: Bool = false, hasTotp: Bool = false) {
        self.id = id
        self.name = name
        self.username = username
        self.domain = domain
        self.notes = notes
        self.hasPassword = hasPassword
        self.hasPrivateKey = hasPrivateKey
        self.hasPassphrase = hasPassphrase
        self.hasTotp = hasTotp
    }

    /// « DOMAINE\utilisateur » ou « utilisateur ».
    public var account: String { domain.isEmpty ? username : "\(domain)\\\(username)" }
}

/// Champ secret d'un identifiant, tel que l'API `reveal` l'attend.
public enum SecretField: String, Sendable {
    case password, privateKey, passphrase
}

public struct TOTPCode: Codable, Sendable, Equatable {
    public let code: String
    public let remaining: Int
    public let period: Int
}

public struct ConnectionTest: Codable, Sendable, Equatable {
    public let address: String
    public let ip: String?
    public let status: String
    public let durationMs: Double
    public let checkedAt: String

    public var reachable: Bool { status == "reachable" }

    public var statusTitle: String {
        switch status {
        case "reachable": return "Port accessible"
        case "refused": return "Connexion refusée"
        case "timeout": return "Délai dépassé"
        case "dns_error": return "Nom introuvable (DNS)"
        case "unreachable": return "Hôte injoignable"
        default: return "Erreur"
        }
    }
}

public struct ServerInfo: Codable, Sendable, Equatable {
    public let user: String
    public let version: String
}

public struct SessionTicket: Codable, Sendable, Equatable {
    public let token: String
    public let `protocol`: String
}

/// Options d'ouverture de session envoyées à `/api/entries/{id}/connect`.
public struct SessionOptions: Codable, Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var dpi: Int
    public var timezone: String
    public var record: Bool
    /// Console Proxmox relayée par guacd (au lieu de noVNC).
    public var native: Bool

    public init(width: Int, height: Int, dpi: Int = 96, timezone: String = TimeZone.current.identifier, record: Bool = false, native: Bool = false) {
        self.width = width
        self.height = height
        self.dpi = dpi
        self.timezone = timezone
        self.record = record
        self.native = native
    }
}

/// Connexion rapide : SSH ou RDP sans fiche.
public struct QuickConnectRequest: Codable, Sendable, Equatable {
    public var kind: EntryKind
    public var host: String
    public var port: Int
    public var username: String
    public var domain: String
    public var password: String
    public var credentialId: String?
    public var width: Int
    public var height: Int
    public var dpi: Int
    public var timezone: String
    public var record: Bool

    public init(kind: EntryKind, host: String, port: Int, username: String = "", domain: String = "", password: String = "",
                credentialId: String? = nil, options: SessionOptions) {
        self.kind = kind
        self.host = host
        self.port = port
        self.username = username
        self.domain = domain
        self.password = password
        self.credentialId = credentialId
        width = options.width
        height = options.height
        dpi = options.dpi
        timezone = options.timezone
        record = options.record
    }
}

public struct AuditEvent: Codable, Identifiable, Sendable, Hashable {
    public let id: Int
    public let at: String
    public let user: String
    public let action: String
    public let target: String
    public let detail: String
}

/// Dates RFC 3339 renvoyées par le serveur (avec ou sans fraction de seconde).
public enum RelayDate {
    public static func parse(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: text) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}

/// Espace de travail : groupe d'entrées ouvertes ensemble (propre à l'utilisateur).
public struct Workspace: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var entryIds: [String]

    public init(id: String = "", name: String, entryIds: [String]) {
        self.id = id
        self.name = name
        self.entryIds = entryIds
    }
}

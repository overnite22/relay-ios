import Foundation

/// Élément d'un dossier distant (index JSON de guacd : chemin → type MIME).
public struct RemoteItem: Identifiable, Hashable, Sendable {
    public let path: String
    public let isDirectory: Bool
    public var id: String { path }
    public var name: String { RemotePath.basename(path) }

    public init(path: String, isDirectory: Bool) {
        self.path = path
        self.isDirectory = isDirectory
    }

    /// Décode un index de dossier ; dossiers d'abord, puis tri naturel par nom.
    public static func parseIndex(_ data: Data) throws -> [RemoteItem] {
        let index = try JSONDecoder().decode([String: String].self, from: data)
        return index.map { RemoteItem(path: $0.key, isDirectory: $0.value == GuacClientCore.directoryMimetype) }
            .sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }
}

public enum RemotePath {
    public static func basename(_ path: String) -> String {
        let trimmed = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
        return trimmed.split(separator: "/").last.map(String.init) ?? "/"
    }

    public static func parent(_ path: String) -> String {
        var trimmed = path
        while trimmed.count > 1 && trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let slash = trimmed.lastIndex(of: "/"), slash != trimmed.startIndex else { return "/" }
        return String(trimmed[..<slash])
    }

    public static func join(_ dir: String, _ name: String) -> String {
        (dir.hasSuffix("/") ? dir : dir + "/") + name
    }
}

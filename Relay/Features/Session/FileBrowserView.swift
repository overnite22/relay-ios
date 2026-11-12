import RelayKit
import SwiftUI
import UniformTypeIdentifiers

enum FileError: LocalizedError {
    case unavailable, notDirectory, tooLarge
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Le transfert de fichiers n'est pas disponible dans cette session."
        case .notDirectory: return "Ce chemin n'est pas un dossier."
        case .tooLarge: return "Fichier trop volumineux (512 Mo au plus)."
        case .remote(let message): return message
        }
    }
}

/// Fichier local à partager (enregistrer dans Fichiers, AirDrop…).
struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Dossier temporaire des fichiers téléchargés (vidé par iOS).
enum LocalFiles {
    static func save(_ data: Data, name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Relay-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let url = dir.appendingPathComponent(safe.isEmpty ? "fichier" : safe)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Navigateur de fichiers d'une session : SFTP (SSH) ou lecteur « Relay » (RDP).
struct FileBrowserView: View {
    let controller: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var path = "/"
    @State private var items: [RemoteItem]?
    @State private var error: String?
    @State private var transfers: [Transfer] = []
    @State private var importing = false
    @State private var shared: SharedFile?

    struct Transfer: Identifiable {
        let id = UUID()
        let name: String
        let upload: Bool
        var done: Int
        let total: Int
        var state: Status
        enum Status: Equatable { case running, ok, failed(String) }
    }

    private var isRDP: Bool { controller.target.kind == .rdp }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if path != "/" {
                        Button {
                            Task { await load(RemotePath.parent(path)) }
                        } label: {
                            Label("Dossier parent", systemImage: "arrow.turn.left.up")
                        }
                        .accessibilityIdentifier("filesParent")
                    }
                    if let items {
                        if items.isEmpty { Text("Dossier vide").foregroundStyle(.secondary) }
                        ForEach(items) { item in row(item) }
                    } else if error == nil {
                        HStack { ProgressView(); Text("Lecture du dossier…") }
                    }
                } header: {
                    Text(path).textCase(nil).font(.caption.monospaced())
                } footer: {
                    if isRDP {
                        Text("Côté Windows, le lecteur « \(controller.filesystem?.name ?? "Relay") » est dans Ce PC. Un fichier copié dans son dossier Download arrive sur l'iPhone.")
                    }
                }
                if let error { StatusBanner(message: error) }
                if !transfers.isEmpty {
                    Section("Transferts") {
                        ForEach(transfers) { t in transferRow(t) }
                    }
                }
            }
            .navigationTitle(isRDP ? "Lecteur \(controller.filesystem?.name ?? "Relay")" : "Fichiers (SFTP)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("OK") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Actualiser", systemImage: "arrow.clockwise") { Task { await load(path) } }
                    Button("Envoyer", systemImage: "square.and.arrow.up") { importing = true }
                        .accessibilityIdentifier("filesUpload")
                }
            }
            .refreshable { await load(path) }
            .task { if items == nil { await load(path) } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { Task { await upload(urls) } }
            }
            .sheet(item: $shared) { file in ShareSheet(url: file.url).presentationDetents([.medium, .large]) }
        }
    }

    private func row(_ item: RemoteItem) -> some View {
        Button {
            if item.isDirectory { Task { await load(item.path) } } else { Task { await download(item) } }
        } label: {
            Label {
                Text(item.name).foregroundStyle(.primary)
            } icon: {
                Image(systemName: item.isDirectory ? "folder.fill" : "doc").foregroundStyle(item.isDirectory ? .yellow : .secondary)
            }
        }
        .accessibilityIdentifier("file-\(item.name)")
    }

    private func transferRow(_ t: Transfer) -> some View {
        HStack {
            Image(systemName: t.upload ? "arrow.up.circle" : "arrow.down.circle")
            VStack(alignment: .leading, spacing: 2) {
                Text(t.name).lineLimit(1)
                switch t.state {
                case .running:
                    if t.total > 0 {
                        ProgressView(value: Double(t.done), total: Double(t.total))
                    } else {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(t.done), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                    }
                case .ok:
                    Text("Terminé").font(.caption).foregroundStyle(.green)
                case .failed(let message):
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .accessibilityIdentifier("transfer-\(t.name)")
    }

    private func load(_ dir: String) async {
        error = nil
        items = nil
        do {
            items = try await controller.list(dir)
            path = dir
        } catch {
            self.error = error.localizedDescription
            items = []
        }
    }

    private func update(_ id: UUID, _ change: (inout Transfer) -> Void) {
        if let index = transfers.firstIndex(where: { $0.id == id }) { change(&transfers[index]) }
    }

    private func download(_ item: RemoteItem) async {
        let t = Transfer(name: item.name, upload: false, done: 0, total: 0, state: .running)
        transfers.insert(t, at: 0)
        do {
            let url = try await controller.download(item.path) { bytes in update(t.id) { $0.done = bytes } }
            update(t.id) { $0.state = .ok }
            shared = SharedFile(url: url)
        } catch {
            update(t.id) { $0.state = .failed(error.localizedDescription) }
        }
    }

    private func upload(_ urls: [URL]) async {
        let dir = path
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let t = Transfer(name: name, upload: true, done: 0, total: size, state: .running)
            transfers.insert(t, at: 0)
            do {
                guard size <= 512 << 20 else { throw FileError.tooLarge }
                let data = try Data(contentsOf: url)
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                try await controller.upload(data, to: RemotePath.join(dir, name), mimetype: mime) { bytes in
                    update(t.id) { $0.done = bytes }
                }
                update(t.id) { $0.state = .ok; $0.done = data.count }
            } catch {
                update(t.id) { $0.state = .failed(error.localizedDescription) }
            }
        }
        if dir == path { await load(dir) }
    }
}

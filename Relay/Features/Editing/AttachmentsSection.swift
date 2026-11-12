import RelayKit
import SwiftUI

/// Pièces jointes d'une entrée : ajout depuis Fichiers, ouverture, partage, suppression (10 Mio par fichier).
struct AttachmentsSection: View {
    let app: AppSession
    let entryId: String
    @State private var items: [Attachment] = []
    @State private var importing = false
    @State private var busy = false
    @State private var error: String?
    @State private var shared: SharedFile?

    var body: some View {
        Section {
            ForEach(items) { item in
                Button {
                    Task { await open(item) }
                } label: {
                    HStack {
                        Image(systemName: "paperclip")
                        VStack(alignment: .leading) {
                            Text(item.name).foregroundStyle(.primary)
                            Text("\(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file)) · \(item.createdAt.shortDate)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions {
                    Button("Supprimer", systemImage: "trash", role: .destructive) { Task { await delete(item) } }
                }
            }
            Button("Joindre un fichier", systemImage: "plus") { importing = true }
                .disabled(busy)
                .accessibilityIdentifier("attachAdd")
            if let error { StatusBanner(message: error) }
        } header: {
            HStack {
                Text("Pièces jointes")
                if busy { ProgressView().controlSize(.small) }
            }
        }
        .task { await load() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await add(urls) } }
        }
        .sheet(item: $shared) { file in ShareSheet(url: file.url).presentationDetents([.medium, .large]) }
    }

    private func load() async {
        guard let client = app.client else { return }
        items = (try? await client.attachments(entryId)) ?? items
    }

    private func add(_ urls: [URL]) async {
        guard let client = app.client else { return }
        busy = true
        defer { busy = false }
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                guard data.count <= 10 << 20 else {
                    error = "« \(url.lastPathComponent) » dépasse 10 Mio."
                    continue
                }
                let added = try await client.addAttachment(entryId, name: url.lastPathComponent, data: data)
                items.insert(added, at: 0)
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func open(_ item: Attachment) async {
        guard let client = app.client else { return }
        busy = true
        defer { busy = false }
        do {
            shared = SharedFile(url: try LocalFiles.save(try await client.attachmentData(entryId, id: item.id), name: item.name))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ item: Attachment) async {
        guard let client = app.client else { return }
        do {
            try await client.deleteAttachment(entryId, id: item.id)
            items.removeAll { $0.id == item.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

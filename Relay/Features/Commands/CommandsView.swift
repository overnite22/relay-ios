import RelayKit
import SwiftUI

/// Diffusion d'une commande SSH sur plusieurs serveurs, exécutée par le serveur Relay.
struct CommandsView: View {
    @Bindable var app: AppSession
    @AppStorage("commandTimeout") private var timeout = 30
    @AppStorage("commandConcurrency") private var concurrency = 10
    @State private var command = ""
    @State private var sudo = false
    @State private var run: CommandRun?
    @State private var starting = false
    @State private var error: String?
    @State private var saved: [SavedCommand] = []
    @State private var naming = false
    @State private var newName = ""
    @State private var poll: Task<Void, Never>?

    private var targets: [Entry] {
        app.tree.entries.filter { app.commandTargets.contains($0.id) && $0.kind == .ssh }
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    CommandTargetsView(app: app)
                } label: {
                    LabeledContent("Serveurs SSH") {
                        Text(targets.isEmpty ? "Aucun" : "\(targets.count) sélectionné(s)")
                    }
                }
                .accessibilityIdentifier("commandTargets")
                if !targets.isEmpty {
                    Text(targets.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            Section {
                TextEditor(text: $command)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .frame(minHeight: 90)
                    .accessibilityIdentifier("commandText")
                Toggle("Exécuter avec sudo", isOn: $sudo)
                Stepper("Délai par serveur : \(timeout) s", value: $timeout, in: 5...600, step: 5)
                Stepper("Connexions en parallèle : \(concurrency)", value: $concurrency, in: 1...50)
            } header: {
                HStack {
                    Text("Commande")
                    Spacer()
                    Menu {
                        if saved.isEmpty { Text("Aucune commande enregistrée") }
                        ForEach(saved) { item in
                            Button(item.name) {
                                command = item.command
                                sudo = item.sudo
                            }
                        }
                        Divider()
                        Button("Enregistrer la commande…", systemImage: "square.and.arrow.down") {
                            newName = ""
                            naming = true
                        }
                        .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        NavigationLink {
                            SavedCommandsView(app: app, saved: $saved)
                        } label: {
                            Label("Gérer la bibliothèque", systemImage: "books.vertical")
                        }
                    } label: {
                        Label("Bibliothèque", systemImage: "books.vertical").font(.caption)
                    }
                    .textCase(nil)
                    .accessibilityIdentifier("commandLibrary")
                }
            } footer: {
                Text("Relay se connecte à chaque serveur avec les identifiants du coffre. Une clé de serveur qui change est refusée.")
            }
            Section {
                Button {
                    Task { await start(targets.map(\.id)) }
                } label: {
                    Label(starting ? "Démarrage…" : "Exécuter", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(starting || targets.isEmpty || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (run.map { !$0.finished } ?? false))
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("commandRun")
            }
            if let error { StatusBanner(message: error) }
            if let run { results(run) }
        }
        .navigationTitle("Commande SSH")
        .toolbar {
            NavigationLink {
                CommandHistoryView(app: app)
            } label: {
                Label("Historique", systemImage: "clock.arrow.circlepath")
            }
            .accessibilityIdentifier("commandHistory")
        }
        .task { await loadSaved() }
        .onAppear(perform: takeDraft)
        .onChange(of: app.commandDraft?.command) { _, _ in takeDraft() }
        .onDisappear { poll?.cancel() }
        .alert("Enregistrer la commande", isPresented: $naming) {
            TextField("Nom", text: $newName)
            Button("Annuler", role: .cancel) {}
            Button("Enregistrer") { Task { await saveCurrent() } }
        }
    }

    @ViewBuilder private func results(_ run: CommandRun) -> some View {
        Section {
            ForEach(run.results ?? []) { result in
                NavigationLink {
                    RunOutputView(app: app, result: result, command: run.command)
                } label: {
                    RunResultRow(result: result)
                }
                .accessibilityIdentifier("result-\(result.name)")
            }
        } header: {
            HStack {
                Text(run.finished ? "Résultats : \(run.ok) réussie(s), \(run.failed) échec(s)" : "En cours…")
                Spacer()
                if run.finished {
                    let failed = (run.results ?? []).filter { $0.status != .ok }.map(\.entryId)
                    if !failed.isEmpty {
                        Button("Relancer les échecs") { Task { await start(failed) } }.font(.caption).textCase(nil)
                    }
                } else {
                    Button("Annuler", role: .destructive) {
                        Task { try? await app.client?.cancelRun(run.id) }
                    }
                    .font(.caption).textCase(nil)
                    .accessibilityIdentifier("commandCancel")
                }
            }
        }
    }

    private func start(_ ids: [String]) async {
        guard let client = app.client else { return }
        starting = true
        error = nil
        defer { starting = false }
        do {
            let request = RunRequest(entryIds: ids, command: command.trimmingCharacters(in: .whitespacesAndNewlines),
                                     sudo: sudo, timeoutSec: timeout, concurrency: concurrency)
            let started = try await client.startRun(request)
            run = started
            follow(started.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Suit l'exécution toutes les secondes jusqu'à la fin.
    private func follow(_ id: String) {
        poll?.cancel()
        poll = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let client = app.client, let current = try? await client.run(id) else { continue }
                run = current
                if current.finished {
                    UINotificationFeedbackGenerator().notificationOccurred(current.failed == 0 ? .success : .warning)
                    return
                }
            }
        }
    }

    private func takeDraft() {
        if let draft = app.commandDraft {
            command = draft.command
            sudo = draft.sudo
            app.commandDraft = nil
        }
    }

    private func loadSaved() async {
        saved = (try? await app.client?.savedCommands()) ?? saved
    }

    private func saveCurrent() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let client = app.client else { return }
        do {
            let item = try await client.saveCommand(SavedCommand(name: name, command: command, sudo: sudo))
            saved.append(item)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct RunResultRow: View {
    let result: RunResult
    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                Text([result.address, result.exitCode.map { "code \($0)" }, result.status.isFinal ? "\(Int(result.durationMs)) ms" : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if !result.error.isEmpty {
                    Text(result.error).font(.caption).foregroundStyle(.red).lineLimit(2)
                } else if let first = result.output.split(separator: "\n").first {
                    Text(first).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder private var icon: some View {
        switch result.status {
        case .pending: Image(systemName: "clock").foregroundStyle(.secondary)
        case .running: ProgressView()
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.orange)
        case .error, .unknown: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .canceled: Image(systemName: "stop.circle").foregroundStyle(.secondary)
        }
    }
}

/// Sortie complète d'un serveur.
struct RunOutputView: View {
    let app: AppSession
    let result: RunResult
    let command: String
    @State private var forgotten = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                RunResultRow(result: result)
                if !result.fingerprint.isEmpty {
                    LabeledContent("Empreinte", value: result.fingerprint).font(.caption.monospaced())
                }
                if result.newHostKey {
                    Label("Clé du serveur mémorisée à cette exécution.", systemImage: "key.fill").font(.caption)
                }
            }
            if result.status == .error && !result.fingerprint.isEmpty || result.hostKeyChanged {
                Section {
                    Button(forgotten ? "Clé oubliée : relancez la commande" : "Oublier la clé mémorisée", systemImage: "key.slash", role: .destructive) {
                        Task {
                            do {
                                try await app.client?.forgetHostKey(address: result.address)
                                forgotten = true
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                    .disabled(forgotten)
                } footer: {
                    Text("À faire seulement si le changement de clé est attendu (réinstallation du serveur).")
                }
            }
            if let error { StatusBanner(message: error) }
            Section {
                ScrollView(.horizontal) {
                    Text(result.output.isEmpty ? "(aucune sortie)" : result.output)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
                if result.truncated { Text("Sortie tronquée par le serveur.").font(.caption).foregroundStyle(.orange) }
            } header: {
                HStack {
                    Text("Sortie")
                    Spacer()
                    CopyButton(label: "la sortie") { result.output }
                }
            }
        }
        .navigationTitle(result.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Choix des serveurs SSH : par dossier ou individuellement.
struct CommandTargetsView: View {
    @Bindable var app: AppSession
    @State private var query = ""

    private var sshEntries: [Entry] {
        let q = query.lowercased()
        return app.tree.entries.filter { $0.kind == .ssh && (q.isEmpty || $0.searchText.contains(q)) }
    }

    var body: some View {
        List {
            Section {
                Button("Tout désélectionner") { app.commandTargets.removeAll() }.disabled(app.commandTargets.isEmpty)
            }
            if query.isEmpty {
                folderSection(nil, depth: 0)
            } else {
                ForEach(sshEntries) { entry in entryRow(entry) }
            }
        }
        .navigationTitle("Serveurs")
        .searchable(text: $query, prompt: "Filtrer")
    }

    private func entries(under folder: String?) -> [Entry] {
        var out = app.tree.entries(in: folder).filter { $0.kind == .ssh }
        for child in app.tree.folders(in: folder) { out += entries(under: child.id) }
        return out
    }

    private func folderSection(_ folder: String?, depth: Int) -> AnyView {
        AnyView(Group {
            ForEach(app.tree.folders(in: folder)) { child in
                let inside = entries(under: child.id)
                if !inside.isEmpty {
                    let all = inside.allSatisfy { app.commandTargets.contains($0.id) }
                    Button {
                        if all { inside.forEach { app.commandTargets.remove($0.id) } } else { inside.forEach { app.commandTargets.insert($0.id) } }
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill").foregroundStyle(.yellow)
                            Text(child.name).fontWeight(.semibold)
                            Spacer()
                            Text("\(inside.count)").font(.caption).foregroundStyle(.secondary)
                            Image(systemName: all ? "checkmark.circle.fill" : "circle").foregroundStyle(all ? Color.relayAccent : .secondary)
                        }
                        .padding(.leading, CGFloat(depth) * 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("targetFolder-\(child.name)")
                    folderSection(child.id, depth: depth + 1)
                }
            }
            ForEach(app.tree.entries(in: folder).filter { $0.kind == .ssh }) { entry in
                entryRow(entry).padding(.leading, CGFloat(depth) * 14)
            }
        })
    }

    private func entryRow(_ entry: Entry) -> some View {
        Button {
            if app.commandTargets.contains(entry.id) { app.commandTargets.remove(entry.id) } else { app.commandTargets.insert(entry.id) }
        } label: {
            HStack {
                EntryRow(entry: entry, status: app.status[entry.id])
                Image(systemName: app.commandTargets.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(app.commandTargets.contains(entry.id) ? Color.relayAccent : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("target-\(entry.name)")
    }
}

struct SavedCommandsView: View {
    let app: AppSession
    @Binding var saved: [SavedCommand]
    @State private var editing: EditingBox<SavedCommand>?
    @State private var error: String?

    var body: some View {
        List {
            if let error { StatusBanner(message: error) }
            ForEach(saved) { item in
                Button {
                    editing = EditingBox(value: item)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(item.name).foregroundStyle(.primary)
                            if item.sudo { Text("sudo").font(.caption2.bold()).foregroundStyle(.orange) }
                        }
                        Text(item.command).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .swipeActions {
                    Button("Supprimer", systemImage: "trash", role: .destructive) {
                        Task {
                            do {
                                try await app.client?.deleteSavedCommand(item.id)
                                saved.removeAll { $0.id == item.id }
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Bibliothèque")
        .toolbar { Button("Ajouter", systemImage: "plus") { editing = EditingBox(value: SavedCommand(name: "", command: "", sudo: false)) } }
        .sheet(item: $editing) { box in
            SavedCommandEditor(app: app, item: box.value) { updated in
                if let index = saved.firstIndex(where: { $0.id == updated.id }) { saved[index] = updated } else { saved.append(updated) }
            }
        }
    }
}

struct SavedCommandEditor: View {
    let app: AppSession
    @State var item: SavedCommand
    let onSave: (SavedCommand) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom", text: $item.name)
                TextEditor(text: $item.command).font(.system(.body, design: .monospaced)).frame(minHeight: 120)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("sudo", isOn: $item.sudo)
                if let error { StatusBanner(message: error) }
            }
            .navigationTitle(item.id.isEmpty ? "Nouvelle commande" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        Task {
                            do {
                                guard let client = app.client else { return }
                                onSave(try await client.saveCommand(item))
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                    .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty || item.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

/// Historique des exécutions (200 dernières côté serveur).
struct CommandHistoryView: View {
    let app: AppSession
    @State private var runs: [CommandRun] = []
    @State private var error: String?

    var body: some View {
        List {
            if let error { StatusBanner(message: error) }
            ForEach(runs) { run in
                NavigationLink {
                    RunDetailView(app: app, runId: run.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(run.command).font(.callout.monospaced()).lineLimit(2)
                        Text("\(run.at.shortDate) · \(run.targets) serveur(s) · \(run.ok) OK · \(run.failed) échec(s)\(run.sudo ? " · sudo" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Historique")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            runs = try await app.client?.runHistory() ?? []
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct RunDetailView: View {
    let app: AppSession
    let runId: String
    @State private var run: CommandRun?
    @State private var error: String?

    var body: some View {
        List {
            if let error { StatusBanner(message: error) }
            if let run {
                Section("Commande") {
                    Text(run.command).font(.callout.monospaced()).textSelection(.enabled)
                    Button("Reprendre dans l'éditeur", systemImage: "arrow.uturn.backward") {
                        app.commandTargets = Set((run.results ?? []).map(\.entryId))
                        app.commandDraft = (run.command, run.sudo)
                    }
                }
                Section("Résultats") {
                    ForEach(run.results ?? []) { result in
                        NavigationLink {
                            RunOutputView(app: app, result: result, command: run.command)
                        } label: {
                            RunResultRow(result: result)
                        }
                    }
                }
            }
        }
        .navigationTitle(run?.at.shortDate ?? "Exécution")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { run = try await app.client?.run(runId) } catch { self.error = error.localizedDescription }
        }
    }
}

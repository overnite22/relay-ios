import Foundation
import RelayKit
import SwiftUI

/// État global : compte appairé, client API, inventaire et disponibilité.
@MainActor @Observable final class AppSession {
    enum Phase: Equatable { case loading, unpaired, paired }

    private(set) var phase: Phase = .loading
    private(set) var client: RelayClient?
    private(set) var account: ServerAccount?
    private(set) var info: ServerInfo?
    private(set) var tree: Tree = .empty
    private(set) var status: [String: ConnectionTest] = [:]
    private(set) var loading = false
    private(set) var errorMessage: String?
    private(set) var recentIds: [String] = []
    private(set) var credentials: [Credential] = []
    /// Sessions ouvertes (elles restent connectées quand on les réduit).
    private(set) var sessions: [SessionController] = []
    /// Session affichée en plein écran (nil = sessions réduites).
    var presentedSessionID: String?
    /// Serveurs cochés pour la diffusion de commandes.
    var commandTargets: Set<String> = []
    /// Commande à reprendre dans l'éditeur (historique, menu d'un dossier).
    var commandDraft: (command: String, sudo: Bool)?
    /// Onglet demandé par une action (ex. « Commande sur ce dossier »).
    var requestedTab: String?
    @ObservationIgnored private var unlockedUntil = Date.distantPast

    private let store: AccountStore
    private let transport: HTTPTransport?
    /// Remplace le tunnel WebSocket (tests UI : flux Guacamole scripté).
    @ObservationIgnored var tunnelOverride: ((SessionTicket) -> GuacTransport)?
    private static let recentsKey = "recentEntryIds"

    init(store: AccountStore, transport: HTTPTransport? = nil) {
        self.store = store
        self.transport = transport
        recentIds = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
    }

    func restore() {
        guard phase == .loading else { return }
        if let account = try? store.load() {
            activate(account)
        } else {
            phase = .unpaired
        }
    }

    /// Enregistre l'appairage après vérification auprès du serveur (`/api/me`).
    func pair(_ account: ServerAccount) async throws -> ServerInfo {
        let client = RelayClient(account: account, transport: transport)
        let info = try await client.me()
        try store.save(account)
        activate(account, client: client, info: info)
        return info
    }

    func unpair() {
        try? store.delete()
        client = nil
        account = nil
        info = nil
        tree = .empty
        status = [:]
        credentials = []
        for session in sessions { session.close() }
        sessions = []
        presentedSessionID = nil
        unlockedUntil = .distantPast
        errorMessage = nil
        phase = .unpaired
    }

    private func activate(_ account: ServerAccount, client: RelayClient? = nil, info: ServerInfo? = nil) {
        self.account = account
        self.client = client ?? RelayClient(account: account, transport: transport)
        self.info = info
        phase = .paired
    }

    /// Recharge l'inventaire et la disponibilité.
    func refresh() async {
        guard let client, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            async let tree = client.tree()
            async let status = client.connectionStatus()
            self.tree = try await tree
            self.status = (try? await status) ?? self.status
            if info == nil { info = try? await client.me() }
            errorMessage = nil
        } catch {
            if case RelayError.cancelled = error { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadCredentials() async {
        guard let client else { return }
        do {
            credentials = try await client.credentials().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            if case RelayError.cancelled = error { return }
            errorMessage = error.localizedDescription
        }
    }

    func credential(_ id: String?) -> Credential? { id.flatMap { cid in credentials.first { $0.id == cid } } }

    var presentedSession: SessionController? { sessions.first { $0.uid == presentedSessionID } }

    /// Ouvre une session, ou ramène au premier plan celle déjà ouverte vers la même cible.
    func open(_ target: SessionTarget) {
        if let existing = sessions.first(where: { $0.target.id == target.id && !$0.isEnded }) {
            presentedSessionID = existing.uid
            return
        }
        let controller = SessionController(target: target, app: self)
        sessions.append(controller)
        presentedSessionID = controller.uid
    }

    /// Ouvre plusieurs entrées (espace de travail) et affiche la première.
    func openAll(_ entries: [Entry]) {
        let targets = entries.filter(\.kind.opensNatively).map { SessionTarget.entry($0, record: false) }
        guard let first = targets.first else { return }
        for target in targets.dropFirst() where !sessions.contains(where: { $0.target.id == target.id && !$0.isEnded }) {
            sessions.append(SessionController(target: target, app: self))
        }
        open(first)
    }

    func closeSession(_ controller: SessionController) {
        controller.close()
        sessions.removeAll { $0 === controller }
        if presentedSessionID == controller.uid { presentedSessionID = sessions.last?.uid }
    }

    func minimizeSessions() { presentedSessionID = nil }

    /// Vrai si les secrets peuvent être affichés sans nouvelle authentification (fenêtre de 60 s).
    var secretsUnlocked: Bool { Date() < unlockedUntil }
    func markUnlocked() { unlockedUntil = Date().addingTimeInterval(60) }
    func lockSecrets() { unlockedUntil = .distantPast }

    /// Copie d'une entrée (réglages compris), nommée « … (copie) ».
    func duplicate(_ entry: Entry) async {
        guard let client else { return }
        do {
            var input = try await client.entryInput(entry.id)
            input.name += " (copie)"
            input.favorite = false
            _ = try await client.saveEntry(input)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reteste le port des entrées (une fois par adresse), 6 à la fois ; progress(fait, total).
    func retest(_ entries: [Entry], progress: @escaping @MainActor (Int, Int) -> Void) async {
        guard let client else { return }
        var seen = Set<String>()
        let targets = entries.filter { $0.kind.isMonitored && seen.insert($0.target).inserted }
        var done = 0
        progress(0, targets.count)
        await withTaskGroup(of: Void.self) { group in
            var iterator = targets.makeIterator()
            func next() -> Bool {
                guard let entry = iterator.next() else { return false }
                group.addTask { _ = try? await client.testConnection(entry.id) }
                return true
            }
            for _ in 0..<6 where next() {}
            while await group.next() != nil {
                done += 1
                progress(done, targets.count)
                _ = next()
            }
        }
        await refreshStatus()
    }

    func refreshStatus() async {
        guard let client else { return }
        if let s = try? await client.connectionStatus() { status = s }
    }

    /// Tunnel Guacamole d'une session, authentifié par le jeton d'appareil.
    func makeTransport(_ ticket: SessionTicket) -> GuacTransport? {
        if let tunnelOverride { return tunnelOverride(ticket) }
        guard let client, let account, let url = client.tunnelURL(token: ticket.token) else { return nil }
        return RelayTunnelTransport(url: url, deviceToken: account.token)
    }

    func noteOpened(_ entryId: String) {
        recentIds.removeAll { $0 == entryId }
        recentIds.insert(entryId, at: 0)
        recentIds = Array(recentIds.prefix(20))
        UserDefaults.standard.set(recentIds, forKey: Self.recentsKey)
    }

    var recentEntries: [Entry] { recentIds.compactMap { tree.entry($0) } }
    var favoriteEntries: [Entry] { tree.entries.filter(\.favorite).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }

    func toggleFavorite(_ entry: Entry) async {
        guard let client else { return }
        do {
            _ = try await client.setFavorite(entry, !entry.favorite)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

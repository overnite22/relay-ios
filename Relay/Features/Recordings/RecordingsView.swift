import RelayKit
import SwiftUI

/// Enregistrements de sessions de l'utilisateur (Relay web → Ouvrir et enregistrer, ou depuis l'app).
struct RecordingsView: View {
    let app: AppSession
    @State private var recordings: [Recording] = []
    @State private var loading = false
    @State private var error: String?
    @State private var playing: Recording?
    @State private var pendingDelete: Recording?

    var body: some View {
        List {
            if let error { StatusBanner(message: error) }
            if recordings.isEmpty && !loading && error == nil {
                ContentUnavailableView("Aucun enregistrement", systemImage: "film",
                                       description: Text("Ouvrez une session avec « Ouvrir et enregistrer » pour la relire ici."))
            }
            ForEach(recordings) { recording in
                Button {
                    playing = recording
                } label: {
                    HStack(spacing: 12) {
                        KindBadge(kind: recording.kind)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recording.name).foregroundStyle(.primary)
                            Text("\(recording.at.shortDate) · \(ByteCountFormatter.string(fromByteCount: Int64(recording.size), countStyle: .file))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if recording.limited {
                            Text("Tronqué").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.orange.opacity(0.15), in: Capsule())
                                .accessibilityLabel("Tronqué à 64 Mio")
                        }
                        Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Color.relayAccent)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("recording-\(recording.name)")
                .swipeActions {
                    Button("Supprimer", systemImage: "trash", role: .destructive) { pendingDelete = recording }
                }
            }
        }
        .overlay { if loading && recordings.isEmpty { ProgressView() } }
        .navigationTitle("Enregistrements")
        .refreshable { await load() }
        .task { await load() }
        .fullScreenCover(item: $playing) { recording in
            RecordingPlayerView(recording: recording, app: app)
        }
        .confirmationDialog("Supprimer cet enregistrement ?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible, presenting: pendingDelete) { recording in
            Button("Supprimer « \(recording.name) »", role: .destructive) { Task { await delete(recording) } }
        } message: { _ in
            Text("Il est supprimé du serveur Relay, pour tous vos appareils.")
        }
    }

    private func load() async {
        guard let client = app.client else { return }
        loading = true
        defer { loading = false }
        do {
            recordings = try await client.recordings()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ recording: Recording) async {
        guard let client = app.client else { return }
        do {
            try await client.deleteRecording(recording.id)
            recordings.removeAll { $0.id == recording.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Lecteur plein écran.
struct RecordingPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let app: AppSession
    @State private var player: RecordingPlayer
    @State private var scrub: Double?

    init(recording: Recording, app: AppSession) {
        self.app = app
        _player = State(initialValue: RecordingPlayer(recording: recording))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                RemoteScreen(view: player.screen)
                switch player.phase {
                case .loading:
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.large).tint(.white)
                        Text("Téléchargement (\(ByteCountFormatter.string(fromByteCount: Int64(player.recording.size), countStyle: .file)))…")
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                case .failed(let message):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.orange)
                        Text(message).multilineTextAlignment(.center)
                        Button("Fermer") { dismiss() }.buttonStyle(.bordered)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                case .ready:
                    EmptyView()
                }
            }
            .safeAreaInset(edge: .bottom) { if player.phase == .ready { controls } }
            .navigationTitle(player.recording.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }.accessibilityIdentifier("playerClose")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text(player.recording.at.shortDate).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await player.load(app.client) }
        .onDisappear { player.stop() }
    }

    private var controls: some View {
        VStack(spacing: 6) {
            Slider(value: Binding(
                get: { scrub ?? Double(player.position) },
                set: { scrub = $0 }
            ), in: 0...Double(max(player.duration, 1))) { editing in
                if !editing, let target = scrub {
                    Task {
                        await player.seek(to: Int(target))
                        scrub = nil
                    }
                }
            }
            .accessibilityIdentifier("playerSlider")
            HStack {
                Text(RecordingTimeline.clock(Int(scrub ?? Double(player.position))))
                    .font(.caption.monospacedDigit()).accessibilityIdentifier("playerPosition")
                Spacer()
                Button {
                    Task { await player.seek(to: player.position - 10_000) }
                } label: { Image(systemName: "gobackward.10") }
                .accessibilityLabel("Reculer de 10 secondes")
                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill").font(.title2).frame(width: 44, height: 44)
                }
                .accessibilityLabel(player.playing ? "Pause" : "Lecture")
                .accessibilityIdentifier("playerToggle")
                Button {
                    Task { await player.seek(to: player.position + 10_000) }
                } label: { Image(systemName: "goforward.10") }
                .accessibilityLabel("Avancer de 10 secondes")
                Spacer()
                Text(RecordingTimeline.clock(player.duration)).font(.caption.monospacedDigit())
            }
            HStack {
                Menu {
                    Picker("Vitesse", selection: $player.speed) {
                        ForEach([0.5, 1, 2, 4, 8], id: \.self) { v in Text(speedLabel(v)).tag(v) }
                    }
                } label: {
                    Label(speedLabel(player.speed), systemImage: "speedometer").font(.callout)
                }
                .accessibilityIdentifier("playerSpeed")
                Spacer()
                Toggle("Sauter les pauses", isOn: $player.skipIdle).toggleStyle(.button).font(.callout)
                    .accessibilityIdentifier("playerSkipIdle")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func speedLabel(_ v: Double) -> String {
        v == 0.5 ? "×0,5" : "×\(Int(v))"
    }
}

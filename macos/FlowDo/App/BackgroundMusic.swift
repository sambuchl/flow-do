import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

/// One local, app-owned track. Engagement transitions never reset playback.
@MainActor
final class BackgroundMusic: ObservableObject {
    @Published private(set) var trackName: String?
    @Published private(set) var enabled: Bool
    @Published private(set) var volume: Double
    @Published private(set) var importing = false
    @Published private(set) var errorMessage: String?
    private let defaults: UserDefaults
    private var player: AVAudioPlayer?
    private var panel: NSOpenPanel?
    private var suspended = false
    private var stopped = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "musicEnabled")
        let saved = (defaults.object(forKey: "musicVolume") as? Double) ?? 0.4
        volume = saved.isFinite ? min(1, max(0, saved)) : 0.4
        if let file = defaults.string(forKey: "musicFile"), UUID(uuidString: file) != nil {
            do {
                player = try makePlayer(url: directory().appendingPathComponent(file + ".mp3"))
                trackName = defaults.string(forKey: "musicName") ?? "Imported MP3"
                updatePlayback()
            } catch { errorMessage = "The saved MP3 could not be loaded. Choose it again." }
        }
    }

    private func directory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("FlowDo/Audio", isDirectory: true)
    }

    private func makePlayer(url: URL) throws -> AVAudioPlayer {
        let result = try AVAudioPlayer(contentsOf: url)
        guard result.duration > 0, result.prepareToPlay() else {
            throw CocoaError(.fileReadCorruptFile)
        }
        result.numberOfLoops = -1
        result.volume = Float(volume)
        return result
    }

    func chooseMP3() {
        guard !importing, !stopped else { return }
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.mp3]
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        picker.prompt = "Import MP3"
        panel = picker
        importing = true
        picker.begin { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                self.panel = nil
                guard response == .OK, let url = picker.url, !self.stopped else {
                    self.importing = false
                    return
                }
                await self.importMP3(url)
            }
        }
    }

    private func importMP3(_ source: URL) async {
        defer { importing = false }
        var destination: URL?
        do {
            let folder = try directory()
            let id = UUID().uuidString
            let target = folder.appendingPathComponent(id + ".mp3")
            destination = target
            // File copying can be slow; keep the menu and engagement timer responsive.
            try await Task.detached(priority: .utility) {
                let access = source.startAccessingSecurityScopedResource()
                defer { if access { source.stopAccessingSecurityScopedResource() } }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                       attributes: [.posixPermissions: 0o700])
                try FileManager.default.copyItem(at: source, to: target)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            }.value
            guard !stopped else { try? FileManager.default.removeItem(at: target); return }
            let replacement = try makePlayer(url: target)
            let previous = player?.url
            player?.stop()
            player = replacement
            trackName = source.lastPathComponent
            defaults.set(id, forKey: "musicFile")
            defaults.set(trackName, forKey: "musicName")
            errorMessage = nil
            setEnabled(true)
            if let previous { try? FileManager.default.removeItem(at: previous) }
        } catch {
            if let destination { try? FileManager.default.removeItem(at: destination) }
            errorMessage = "Could not import this MP3. Choose a readable audio file. Your previous track is kept."
        }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        defaults.set(value, forKey: "musicEnabled")
        updatePlayback()
    }

    func setVolume(_ value: Double) {
        guard value.isFinite else { return }
        volume = min(1, max(0, value))
        defaults.set(volume, forKey: "musicVolume")
        player?.volume = Float(volume)
    }

    func setSuspended(_ value: Bool) {
        suspended = value
        updatePlayback()
    }

    private func updatePlayback() {
        guard let player else { return }
        if enabled && !suspended && !stopped {
            if !player.isPlaying && !player.play() {
                errorMessage = "Playback could not start. Try turning music off and on."
            }
        } else { player.pause() }
    }

    func removeTrack() {
        guard !importing else { return }
        let url = player?.url
        player?.stop()
        player = nil
        trackName = nil
        setEnabled(false)
        defaults.removeObject(forKey: "musicFile")
        defaults.removeObject(forKey: "musicName")
        errorMessage = nil
        if let url {
            do { try FileManager.default.removeItem(at: url) }
            catch { errorMessage = "Playback stopped, but the local audio copy could not be removed." }
        }
    }

    func shutdown() {
        stopped = true
        panel?.cancel(nil)
        player?.stop()
    }
}

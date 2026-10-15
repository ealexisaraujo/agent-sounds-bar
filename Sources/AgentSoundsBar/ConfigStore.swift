import Foundation
import Observation

/// One hook event the widget controls. `key` is the name passed to `play-sound`.
struct SoundEvent: Identifiable {
    let key: String
    let title: String
    let detail: String
    let defaultSound: String
    let hook: String
    let explanation: String
    var id: String { key }

    static func title(for key: String) -> String {
        all.first { $0.key == key }?.title ?? key
    }

    static let all: [SoundEvent] = [
        SoundEvent(key: "session_start", title: "Session start",
                   detail: "Agent session opens", defaultSound: SoundLibrary.system("Hero"),
                   hook: "SessionStart",
                   explanation: "Plays when an interactive agent session starts. The hook only runs in a real terminal ([ -t 0 ]), so background runs stay quiet."),
        SoundEvent(key: "user_prompt_submit", title: "Prompt sent",
                   detail: "You submit a prompt", defaultSound: SoundLibrary.system("Tink"),
                   hook: "UserPromptSubmit",
                   explanation: "Plays every time you send a prompt, as an acknowledgement that the agent received it."),
        SoundEvent(key: "stop", title: "Task complete",
                   detail: "Agent finishes responding", defaultSound: SoundLibrary.system("Glass"),
                   hook: "Stop",
                   explanation: "Plays when the agent finishes its turn. play-sound reads the transcript first and switches to the Rate limit / error sound if it ended on a usage or overload error."),
        SoundEvent(key: "stop_error", title: "Rate limit / error",
                   detail: "Finished because of a usage or overload error", defaultSound: SoundLibrary.system("Basso"),
                   hook: "Stop",
                   explanation: "Not a hook of its own: it replaces the Task complete sound when the last 50 transcript lines contain a rate-limit, 429, 529 or overload error."),
        SoundEvent(key: "notification", title: "Needs attention",
                   detail: "Agent asks for permission or input", defaultSound: SoundLibrary.system("Ping"),
                   hook: "Notification",
                   explanation: "Plays when the agent is waiting on you, for example for a permission prompt. Codex has no Notification hook, so this only fires from Claude Code."),
    ]
}

struct EventSetting: Codable, Equatable {
    var enabled: Bool
    var sound: String
}

/// On-disk format shared with the `play-sound` script. Decoding is lenient so a
/// hand-edited or partial file still loads.
struct SoundConfig: Codable, Equatable {
    var muted: Bool
    var volume: Double
    var events: [String: EventSetting]

    static var defaults: SoundConfig {
        var events: [String: EventSetting] = [:]
        for e in SoundEvent.all {
            events[e.key] = EventSetting(enabled: true, sound: e.defaultSound)
        }
        return SoundConfig(muted: false, volume: 0.6, events: events)
    }

    init(muted: Bool, volume: Double, events: [String: EventSetting]) {
        self.muted = muted
        self.volume = volume
        self.events = events
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SoundConfig.defaults
        muted = (try? c.decodeIfPresent(Bool.self, forKey: .muted)) ?? d.muted
        let v = (try? c.decodeIfPresent(Double.self, forKey: .volume)) ?? d.volume
        volume = min(max(v, 0), 1)
        let decoded = (try? c.decodeIfPresent([String: EventSetting].self, forKey: .events)) ?? [:]
        events = d.events.merging(decoded) { _, mine in mine }
    }
}

enum Paths {
    static var home: URL {
        if let override = ProcessInfo.processInfo.environment["AGENT_SOUNDS_HOME"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/agent-sounds", isDirectory: true)
    }
    /// The user's real home, overridable so tests and simulations never touch it.
    static var userHome: URL {
        if let o = ProcessInfo.processInfo.environment["AGENT_SOUNDS_USER_HOME"] {
            return URL(fileURLWithPath: o, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
    static var config: URL { home.appendingPathComponent("config.json") }
    static var connections: URL { home.appendingPathComponent("connections.json") }
    static var sounds: URL { home.appendingPathComponent("sounds", isDirectory: true) }
    static var history: URL { home.appendingPathComponent("history.log") }
    static var cli: URL { home.appendingPathComponent("bin/play-sound") }
}

/// Owns the config file. The UI mutates through `update`, which saves
/// atomically; a directory watcher picks up edits made by hand or by other tools.
@Observable
final class ConfigStore {
    private(set) var config: SoundConfig = .defaults
    private(set) var lastError: String?

    private var watcher: DispatchSourceFileSystemObject?
    private var lastWritten: Data?

    init() {
        try? FileManager.default.createDirectory(at: Paths.sounds, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: Paths.config.path) {
            reload()
        } else {
            save()
        }
        startWatching()
    }

    deinit { watcher?.cancel() }

    func update(_ change: (inout SoundConfig) -> Void) {
        var next = config
        change(&next)
        guard next != config else { return }
        config = next
        save()
    }

    private func save() {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(config)
            try data.write(to: Paths.config, options: .atomic)
            lastWritten = data
            lastError = nil
        } catch {
            lastError = "Could not save settings: \(error.localizedDescription)"
        }
    }

    private func reload() {
        guard let data = try? Data(contentsOf: Paths.config), data != lastWritten else { return }
        do {
            let loaded = try JSONDecoder().decode(SoundConfig.self, from: data)
            lastWritten = data
            lastError = nil
            if loaded != config { config = loaded }
        } catch {
            // Keep the last good config; the script falls back to defaults on its own.
            lastError = "config.json is not valid JSON"
        }
    }

    /// Atomic writes replace the file, so watch the directory rather than the file.
    private func startWatching() {
        let fd = open(Paths.home.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in self?.reload() }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }
}

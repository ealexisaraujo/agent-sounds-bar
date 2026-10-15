import Foundation
import AppKit
import UniformTypeIdentifiers

enum SoundLibrary {
    static let extensions: Set<String> = ["wav", "mp3", "aiff", "aif", "m4a", "caf"]

    /// The sounds every Mac ships. The defaults use these, so the app bundles no audio of its own.
    static let systemFolder = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)

    /// Absolute path of a built-in macOS sound, for example "Glass" -> /System/Library/Sounds/Glass.aiff.
    static func system(_ name: String) -> String {
        systemFolder.appendingPathComponent("\(name).aiff").path
    }

    /// Everything selectable: the user's sounds (file names), then the macOS sounds (absolute paths).
    static func available() -> [String] { user() + builtIn() }

    /// File names in the user's sounds folder that afplay can play, sorted.
    static func user() -> [String] {
        audioFiles(in: Paths.sounds).map(\.lastPathComponent)
    }

    static func builtIn() -> [String] {
        audioFiles(in: systemFolder).map(\.path)
    }

    static func isBuiltIn(_ sound: String) -> Bool { sound.hasPrefix(systemFolder.path + "/") }

    private static func audioFiles(in folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        return urls
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// "mysound.wav" -> "mysound", "/System/Library/Sounds/Glass.aiff" -> "Glass"
    static func display(_ sound: String) -> String {
        ((sound as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// Copies a user-chosen audio file into the sounds folder and returns its file name.
    static func add(_ source: URL) -> String? {
        let fm = FileManager.default
        try? fm.createDirectory(at: Paths.sounds, withIntermediateDirectories: true)
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var name = source.lastPathComponent
        var n = 2
        while fm.fileExists(atPath: Paths.sounds.appendingPathComponent(name).path) {
            name = "\(base)-\(n).\(ext)"
            n += 1
        }
        do { try fm.copyItem(at: source, to: Paths.sounds.appendingPathComponent(name)) } catch { return nil }
        return name
    }

    static func addViaPanel() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Add a sound"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return add(url)
    }

    static func url(for sound: String) -> URL {
        sound.hasPrefix("/") ? URL(fileURLWithPath: sound) : Paths.sounds.appendingPathComponent(sound)
    }
}

/// Plays previews with afplay so they behave exactly like the hook does,
/// ignoring mute so the user can audition sounds while muted.
final class Previewer {
    private var process: Process?

    func play(sound: String, volume: Double) {
        process?.terminate()
        let file = SoundLibrary.url(for: sound)
        guard FileManager.default.fileExists(atPath: file.path), volume > 0 else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        p.arguments = ["-v", String(format: "%.3f", volume), file.path]
        try? p.run()
        process = p
    }
}

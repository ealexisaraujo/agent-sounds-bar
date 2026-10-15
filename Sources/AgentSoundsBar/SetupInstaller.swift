import Foundation

enum SetupStatus: Equatable {
    case notInstalled   // play-sound is missing
    case outdated       // installed, but the app bundles a newer version
    case ready
}

struct StepResult: Identifiable {
    let id = UUID()
    let title: String
    let ok: Bool
    let detail: String
}

/// Puts everything the hooks need under ~/.config/agent-sounds, from files bundled in the app.
struct SetupInstaller {
    var resources: URL?

    init(resources: URL? = SetupInstaller.defaultResources()) { self.resources = resources }

    static func defaultResources() -> URL? {
        let fm = FileManager.default
        if let o = ProcessInfo.processInfo.environment["AGENT_SOUNDS_RESOURCES"] {
            return URL(fileURLWithPath: o, isDirectory: true)
        }
        if let r = Bundle.main.resourceURL, fm.fileExists(atPath: r.appendingPathComponent("play-sound").path) { return r }
        return nil
    }

    // MARK: Status

    static func cliVersion(at url: URL) -> Int? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").prefix(5) where line.contains("agent-sounds-cli-version:") {
            return Int(line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "")
        }
        return nil
    }

    var bundledVersion: Int? { resources.flatMap { Self.cliVersion(at: $0.appendingPathComponent("play-sound")) } }
    var installedVersion: Int? { Self.cliVersion(at: Paths.cli) }

    func status() -> SetupStatus {
        guard FileManager.default.isExecutableFile(atPath: Paths.cli.path) else { return .notInstalled }
        if let b = bundledVersion, b > (installedVersion ?? 0) { return .outdated }
        return .ready
    }

    /// Where `play-sound` will find jq: macOS 15+ ships it in /usr/bin.
    static var jqPath: String? {
        ["/usr/bin/jq", "/opt/homebrew/bin/jq", "/usr/local/bin/jq"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    // MARK: Install

    func install() -> [StepResult] {
        let fm = FileManager.default
        var results: [StepResult] = []

        func step(_ title: String, _ body: () throws -> String) {
            do { results.append(StepResult(title: title, ok: true, detail: try body())) }
            catch { results.append(StepResult(title: title, ok: false, detail: error.localizedDescription)) }
        }

        step("Create the settings folder") {
            for d in [Paths.home, Paths.cli.deletingLastPathComponent(), Paths.sounds] {
                try fm.createDirectory(at: d, withIntermediateDirectories: true)
            }
            return Self.tilde(Paths.home.path)
        }

        step("Install the play-sound command") {
            guard let res = resources else { throw SetupError.noResources }
            try installCLI(from: res)
            return Self.tilde(Paths.cli.path)
        }

        step("Add the starter sounds") {
            guard let res = resources else { throw SetupError.noResources }
            // Release builds bundle no audio and default to the macOS sounds; a local build can
            // still ship its own by putting files in Resources/sounds.
            let src = res.appendingPathComponent("sounds")
            guard fm.fileExists(atPath: src.path) else { return "Using the built-in macOS sounds" }
            let files = (try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)) ?? []
            var added = 0
            for f in files where SoundLibrary.extensions.contains(f.pathExtension.lowercased()) {
                let dest = Paths.sounds.appendingPathComponent(f.lastPathComponent)
                if !fm.fileExists(atPath: dest.path) { try fm.copyItem(at: f, to: dest); added += 1 }
            }
            return added == 0 ? "Already there" : "\(added) sound\(added == 1 ? "" : "s") added"
        }

        step("Write the default settings") {
            if fm.fileExists(atPath: Paths.config.path) {
                // The app writes its defaults at launch, so only call it "yours" if it was changed.
                let current = (try? Data(contentsOf: Paths.config)).flatMap { try? JSONDecoder().decode(SoundConfig.self, from: $0) }
                return current == SoundConfig.defaults ? "Volume 60%, a sound for each event" : "Kept your saved settings"
            }
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(SoundConfig.defaults).write(to: Paths.config, options: .atomic)
            return "Volume 60%"
        }

        step("Check that jq is available") {
            guard let p = Self.jqPath else { throw SetupError.noJQ }
            return p
        }

        return results
    }

    static func tilde(_ path: String) -> String {
        path.replacingOccurrences(of: Paths.userHome.path, with: "~")
    }

    /// Replace the installed script when the bundled one is newer. Used silently at launch.
    @discardableResult
    func updateCLIIfNeeded() -> Bool {
        guard status() == .outdated, let res = resources else { return false }
        return (try? installCLI(from: res)) != nil
    }

    private func installCLI(from res: URL) throws {
        let fm = FileManager.default
        let src = res.appendingPathComponent("play-sound")
        guard fm.fileExists(atPath: src.path) else { throw SetupError.noResources }
        try fm.createDirectory(at: Paths.cli.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: Paths.cli)
        try fm.copyItem(at: src, to: Paths.cli)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: Paths.cli.path)
    }
}

enum SetupError: LocalizedError {
    case noResources, noJQ

    var errorDescription: String? {
        switch self {
        case .noResources: return "The app's bundled files were not found. Rebuild with ./build.sh."
        case .noJQ: return "jq was not found. macOS 15 and later include it; on older versions run: brew install jq"
        }
    }
}

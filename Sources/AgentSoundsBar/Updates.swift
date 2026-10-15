import Foundation
import AppKit
import Observation

/// Which releases the user wants to hear about. Beta also offers GitHub prereleases.
enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable, beta

    static let defaultsKey = "updateChannel"
    var id: String { rawValue }
    var title: String { self == .stable ? "Stable" : "Beta" }
    var detail: String {
        self == .stable ? "Only finished releases." : "Finished releases plus beta previews."
    }

    /// Saved choice, else beta when this build is itself a prerelease.
    static func current(appVersion: AppVersion?) -> UpdateChannel {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey), let c = UpdateChannel(rawValue: raw) { return c }
        return appVersion?.isPrerelease == true ? .beta : .stable
    }
}

/// Semantic version as used in release tags: "v1.2.3" or "1.2.3-beta.1".
struct AppVersion: Comparable, CustomStringConvertible {
    let core: [Int]
    let prerelease: [String]

    init?(_ text: String) {
        var s = text.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        let parts = s.split(separator: "-", maxSplits: 1)
        guard let first = parts.first else { return nil }
        let nums = first.split(separator: ".").map { Int($0) }
        guard !nums.isEmpty, nums.count <= 3, nums.allSatisfy({ $0 != nil }) else { return nil }
        core = nums.compactMap { $0 } + Array(repeating: 0, count: 3 - nums.count)
        prerelease = parts.count > 1 ? parts[1].split(separator: ".").map(String.init) : []
    }

    var isPrerelease: Bool { !prerelease.isEmpty }
    var description: String {
        core.map(String.init).joined(separator: ".") + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: "."))
    }

    /// SemVer precedence: a prerelease sorts before its release; identifiers compare numerically when both are numbers.
    static func < (a: AppVersion, b: AppVersion) -> Bool {
        if a.core != b.core { return a.core.lexicographicallyPrecedes(b.core) }
        if a.prerelease.isEmpty || b.prerelease.isEmpty { return !a.prerelease.isEmpty && b.prerelease.isEmpty }
        for (x, y) in zip(a.prerelease, b.prerelease) where x != y {
            switch (Int(x), Int(y)) {
            case let (i?, j?): return i < j
            case (_?, nil): return true
            case (nil, _?): return false
            default: return x < y
            }
        }
        return a.prerelease.count < b.prerelease.count
    }

    static func == (a: AppVersion, b: AppVersion) -> Bool { a.core == b.core && a.prerelease == b.prerelease }

    static var running: AppVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }
}

/// The parts of the GitHub Releases API this app reads.
struct Release: Decodable, Equatable {
    struct Asset: Decodable, Equatable {
        let name: String
        let browserDownloadURL: URL
        enum CodingKeys: String, CodingKey { case name, browserDownloadURL = "browser_download_url" }
    }

    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let body: String?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", htmlURL = "html_url", draft, prerelease, body, assets
    }

    var version: AppVersion? { AppVersion(tagName) }
    var zip: Asset? { assets.first { $0.name.hasSuffix(".zip") } }

    /// The newest release the channel allows that is newer than `current`.
    static func newest(in releases: [Release], channel: UpdateChannel, newerThan current: AppVersion) -> Release? {
        releases
            .filter { !$0.draft && (channel == .beta || !$0.prerelease) }
            .compactMap { r in r.version.map { (r, $0) } }
            .filter { $0.1 > current }
            .max { $0.1 < $1.1 }?.0
    }
}

/// How this copy was installed, which decides how an update is applied.
enum InstallSource: Equatable {
    case homebrew(brew: URL)
    case direct

    static let caskToken = "agent-sounds-bar"
    static let caskName = "ealexisaraujo/tap/agent-sounds-bar"

    /// Homebrew when the cask is registered in a Caskroom and this copy runs from an Applications folder
    /// (where the cask puts it). A copy run from build/ or elsewhere counts as a direct install.
    static func detect(bundlePath: String = Bundle.main.bundlePath) -> InstallSource {
        let fm = FileManager.default
        let inApplications = bundlePath.hasPrefix("/Applications/")
            || bundlePath.hasPrefix(fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path + "/")
        guard inApplications else { return .direct }
        for prefix in ["/opt/homebrew", "/usr/local"] {
            let brew = URL(fileURLWithPath: "\(prefix)/bin/brew")
            if fm.fileExists(atPath: "\(prefix)/Caskroom/\(caskToken)"), fm.isExecutableFile(atPath: brew.path) {
                return .homebrew(brew: brew)
            }
        }
        return .direct
    }

    var title: String {
        switch self {
        case .homebrew: return "Homebrew"
        case .direct: return "Direct download"
        }
    }
}

/// Checks GitHub Releases for a newer version on the chosen channel and applies it:
/// Homebrew installs upgrade in place and relaunch; direct installs open the download.
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()
    static let repo = "ealexisaraujo/agent-sounds-bar"
    static let interval: TimeInterval = 24 * 60 * 60

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case installing(String)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastChecked: Date?
    /// Set by a check the user asked for, so "You're up to date" is only shown then.
    private(set) var manual = false
    let current = AppVersion.running
    let source = InstallSource.detect()

    var channel: UpdateChannel {
        didSet {
            UserDefaults.standard.set(channel.rawValue, forKey: UpdateChannel.defaultsKey)
            if channel != oldValue { check(manual: false) }
        }
    }

    var automatic: Bool {
        didSet { UserDefaults.standard.set(automatic, forKey: "automaticUpdateChecks") }
    }

    @ObservationIgnored private var timer: Timer?

    init() {
        channel = UpdateChannel.current(appVersion: AppVersion.running)
        automatic = UserDefaults.standard.object(forKey: "automaticUpdateChecks") as? Bool ?? true
    }

    var available: Release? {
        if case .available(let r) = state { return r }
        return nil
    }

    /// Checks shortly after launch and then once a day while automatic checks are on.
    func start() {
        timer?.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.automatic else { return }
            self.check(manual: false)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            guard let self, self.automatic else { return }
            if Date().timeIntervalSince(self.lastChecked ?? .distantPast) >= Self.interval { self.check(manual: false) }
        }
    }

    func check(manual: Bool) {
        if case .installing = state { return }
        guard let current else { state = .failed("This build has no version number."); return }
        self.manual = manual
        state = .checking
        Self.fetchReleases { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.lastChecked = Date()
                switch result {
                case .success(let releases):
                    if let r = Release.newest(in: releases, channel: self.channel, newerThan: current) {
                        self.state = .available(r)
                    } else {
                        self.state = .upToDate
                    }
                case .failure(let error):
                    // Background failures (offline, rate limit) stay quiet; the next check retries.
                    self.state = manual ? .failed(error.localizedDescription) : .idle
                }
            }
        }
    }

    func dismiss() { state = .idle }

    /// True when Install can upgrade in place; otherwise it opens the download.
    /// The Homebrew cask only carries stable releases, so a beta is always a download.
    func upgradesInPlace(_ release: Release) -> Bool {
        if case .homebrew = source { return !release.prerelease }
        return false
    }

    func install() {
        guard let release = available else { return }
        switch source {
        case .homebrew(let brew) where upgradesInPlace(release):
            state = .installing("Updating with Homebrew...")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                // `brew update` first: upgrade alone may skip a tap fetched within the last day.
                let result = Self.run(brew, ["update", "--quiet"]).flatMap { _ in
                    Self.run(brew, ["upgrade", "--cask", InstallSource.caskName])
                }
                DispatchQueue.main.async {
                    switch result {
                    case .success: Self.relaunch()
                    case .failure(let e): self?.state = .failed(e.localizedDescription)
                    }
                }
            }
        default:
            NSWorkspace.shared.open(release.zip?.browserDownloadURL ?? release.htmlURL)
        }
    }

    // MARK: Plumbing

    static func fetchReleases(_ done: @escaping (Result<[Release], Error>) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=30")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("AgentSoundsBar/\(AppVersion.running?.description ?? "dev")", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error { return done(.failure(error)) }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200, let data else { return done(.failure(UpdateError.http(code))) }
            done(Result { try JSONDecoder().decode([Release].self, from: data) })
        }.resume()
    }

    /// Runs brew with a PATH it can work with; launchd gives apps a minimal environment.
    private static func run(_ tool: URL, _ args: [String]) -> Result<Void, Error> {
        let p = Process()
        p.executableURL = tool
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(tool.deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        p.environment = env
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        do { try p.run() } catch { return .failure(error) }
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(data: stderr, encoding: .utf8)?
                .split(separator: "\n").last { $0.contains("Error") }.map(String.init)
            return .failure(UpdateError.brew(msg ?? "brew \(args.first ?? "") failed (\(p.terminationStatus))"))
        }
        return .success(())
    }

    /// The upgraded bundle sits at the same path; open it once this process has exited.
    private static func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }
}

enum UpdateError: LocalizedError {
    case http(Int), brew(String)

    var errorDescription: String? {
        switch self {
        case .http(403), .http(429): return "GitHub is rate limiting update checks. Try again later."
        case .http(404): return "No releases were found."
        case .http(let c): return "GitHub answered with HTTP \(c)."
        case .brew(let m): return m
        }
    }
}

import Foundation

/// Command line entry points, so setup and hook wiring work (and can be tested) without the GUI.
///   AgentSoundsBar setup [--dry-run]
///   AgentSoundsBar status
///   AgentSoundsBar connect <claude|codex|all> [--dry-run]
///   AgentSoundsBar disconnect <claude|codex|all> [--dry-run]
///   AgentSoundsBar version | check-update [--beta]
enum CLI {
    static let commands: Set<String> = ["setup", "status", "connect", "disconnect", "version", "check-update", "help"]

    /// Returns false when the app should launch normally.
    static func runIfRequested(_ args: [String] = Array(CommandLine.arguments.dropFirst())) -> Bool {
        guard let cmd = args.first, commands.contains(cmd) else { return false }
        let rest = Array(args.dropFirst())
        let dry = rest.contains("--dry-run")
        let targets = rest.filter { !$0.hasPrefix("--") }
        let code: Int32
        switch cmd {
        case "setup": code = setup(dry: dry)
        case "status": code = status()
        case "connect": code = wire(targets, dry: dry, disconnect: false)
        case "disconnect": code = wire(targets, dry: dry, disconnect: true)
        case "version": print(AppVersion.running?.description ?? "dev"); code = 0
        case "check-update": code = checkUpdate(channel: rest.contains("--beta") ? .beta : .stable)
        default: print(usage); code = 0
        }
        exit(code)
    }

    static let usage = """
    usage: AgentSoundsBar setup [--dry-run]
           AgentSoundsBar status
           AgentSoundsBar connect <claude|codex|all> [--dry-run]
           AgentSoundsBar disconnect <claude|codex|all> [--dry-run]
           AgentSoundsBar version
           AgentSoundsBar check-update [--beta]
    """

    private static func setup(dry: Bool) -> Int32 {
        let installer = SetupInstaller()
        if dry {
            print("Would install into \(Paths.home.path): play-sound, default settings (existing files are kept).")
            print("Bundled resources: \(installer.resources?.path ?? "NOT FOUND")")
            return 0
        }
        let results = installer.install()
        for r in results { print("\(r.ok ? "ok  " : "FAIL") \(r.title): \(r.detail)") }
        return results.allSatisfy(\.ok) ? 0 : 1
    }

    /// Exit 0 when up to date, 10 when an update exists, 1 when the check failed.
    private static func checkUpdate(channel: UpdateChannel) -> Int32 {
        let current = AppVersion.running ?? AppVersion("0.0.0")!
        let done = DispatchSemaphore(value: 0)
        var result: Result<[Release], Error> = .success([])
        UpdateChecker.fetchReleases { result = $0; done.signal() }
        done.wait()
        switch result {
        case .failure(let e):
            print("check failed: \(e.localizedDescription)")
            return 1
        case .success(let releases):
            print("current \(current), channel \(channel.rawValue), installed via \(InstallSource.detect().title)")
            guard let r = Release.newest(in: releases, channel: channel, newerThan: current) else {
                print("up to date")
                return 0
            }
            print("update available: \(r.tagName)\(r.prerelease ? " (beta)" : "")  \(r.zip?.browserDownloadURL.absoluteString ?? r.htmlURL.absoluteString)")
            return 10
        }
    }

    private static func status() -> Int32 {
        let installer = SetupInstaller()
        print("Setup: \(installer.status())  (installed v\(installer.installedVersion.map(String.init) ?? "-"), bundled v\(installer.bundledVersion.map(String.init) ?? "-"))")
        print("jq: \(SetupInstaller.jqPath ?? "missing")")
        for w in WiringScanner.scan() {
            print("\(w.spec.name): \(w.state)")
            for h in w.hooks { print("  \(h.hook): \(h.status.label)") }
        }
        return 0
    }

    private static func wire(_ targets: [String], dry: Bool, disconnect: Bool) -> Int32 {
        guard let t = targets.first else { print(usage); return 2 }
        let specs = t == "all" ? AgentSpec.all : AgentSpec.named(t).map { [$0] } ?? []
        guard !specs.isEmpty else { print("unknown agent: \(t)"); return 2 }
        if !disconnect, SetupInstaller().status() == .notInstalled {
            print("play-sound is not installed yet. Run: AgentSoundsBar setup")
            return 1
        }
        var failed = false
        for spec in specs {
            guard spec.installed else { print("\(spec.name): not installed, skipped"); continue }
            do {
                let plan = disconnect ? try HookConnector.planDisconnect(spec) : try HookConnector.planConnect(spec)
                print("\(spec.name) (\(spec.file.path))")
                if plan.isNoOp { print("  nothing to change") }
                for c in plan.changes {
                    print("  \(c.kind.rawValue) \(c.hook)\(c.to.map { ": \($0)" } ?? "")")
                }
                for w in plan.warnings { print("  warning: \(w)") }
                if dry {
                    let d = HookConnector.diff(old: plan.oldText, new: plan.newText)
                    if !d.isEmpty { print(d.split(separator: "\n").map { "    \($0)" }.joined(separator: "\n")) }
                    continue
                }
                if let backup = try HookConnector.apply(plan) { print("  backup: \(backup.path)") }
            } catch {
                print("\(spec.name): \(error)")
                failed = true
            }
        }
        return failed ? 1 : 0
    }
}

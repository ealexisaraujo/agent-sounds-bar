import SwiftUI
import AppKit
import Observation

/// What the Connect button will do for one agent, computed ahead of time so the UI can show it.
struct ConnectPreview {
    var summary: String
    var warnings: [String]
    var items: [String]      // one readable line per hook that will change
    var error: String?
}

/// Shared state for installation and agent wiring. One instance, so the popover, the wizard
/// and the configuration window always agree.
@Observable
final class SetupModel {
    static let shared = SetupModel()

    private(set) var status: SetupStatus = .notInstalled
    private(set) var jqPath: String?
    private(set) var agents: [AgentWiring] = []
    private(set) var previews: [String: ConnectPreview] = [:]
    private(set) var installResults: [StepResult] = []
    private(set) var lastBackup: [String: String] = [:]
    var message: String?

    @ObservationIgnored let installer = SetupInstaller()
    @ObservationIgnored private let completedKey = "onboardingCompleted"

    init() { refresh() }

    var onboardingCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: completedKey) }
        set { UserDefaults.standard.set(newValue, forKey: completedKey) }
    }

    var connectedAgents: [AgentWiring] { agents.filter { $0.state == .connected } }
    var installedAgents: [AgentWiring] { agents.filter { $0.state != .notInstalled } }
    var driftedAgents: [AgentWiring] { agents.filter { $0.state == .drifted } }

    func refresh() {
        status = installer.status()
        jqPath = SetupInstaller.jqPath
        agents = WiringScanner.scan()
        var p: [String: ConnectPreview] = [:]
        for w in agents where w.state != .notInstalled {
            p[w.spec.id] = Self.preview(for: w.spec)
        }
        previews = p
    }

    func runInstall() {
        installResults = installer.install()
        refresh()
    }

    /// Silent upkeep at launch: refresh the installed script when the app ships a newer one.
    func selfHeal() {
        installer.updateCLIIfNeeded()
        refresh()
    }

    func connect(_ spec: AgentSpec) {
        do {
            let plan = try HookConnector.planConnect(spec)
            if let backup = try HookConnector.apply(plan) { lastBackup[spec.id] = backup.path }
            message = nil
        } catch {
            message = "\(spec.name): \(error)"
        }
        refresh()
    }

    func disconnect(_ spec: AgentSpec) {
        do {
            let plan = try HookConnector.planDisconnect(spec)
            if let backup = try HookConnector.apply(plan) { lastBackup[spec.id] = backup.path }
            message = nil
        } catch {
            message = "\(spec.name): \(error)"
        }
        refresh()
    }

    private static func preview(for spec: AgentSpec) -> ConnectPreview {
        do {
            let plan = try HookConnector.planConnect(spec)
            let add = plan.changes.filter { $0.kind == .add }.count
            let swap = plan.changes.filter { $0.kind == .replaceLegacy }.count
            let upd = plan.changes.filter { $0.kind == .update }.count
            var parts: [String] = []
            if add > 0 { parts.append("add \(add) hook\(add == 1 ? "" : "s")") }
            if swap > 0 { parts.append("take over \(swap) existing sound hook\(swap == 1 ? "" : "s")") }
            if upd > 0 { parts.append("update \(upd)") }
            let summary = parts.isEmpty ? "Already up to date" : "Will " + parts.joined(separator: ", ")
            let home = Paths.userHome.path
            let items = plan.changes.map { c -> String in
                let verb: String
                switch c.kind {
                case .add: verb = "Add"
                case .replaceLegacy: verb = "Replace"
                case .update: verb = "Update"
                case .restore: verb = "Restore"
                case .remove: verb = "Remove"
                }
                let cmd = (c.to ?? c.from ?? "").replacingOccurrences(of: home, with: "~")
                return "\(verb) \(c.hook)\n  \(cmd)"
            }
            return ConnectPreview(summary: summary, warnings: plan.warnings, items: items, error: nil)
        } catch {
            return ConnectPreview(summary: "Can't change this file", warnings: [], items: [], error: "\(error)")
        }
    }
}

/// The single set of stores the whole app shares, including the AppKit side (delegate, wizard window).
final class AppEnvironment {
    static let shared = AppEnvironment()
    let store = ConfigStore()
    let activity = ActivityStore()
    let previewer = Previewer()
    let setup = SetupModel.shared
    let updates = UpdateChecker.shared
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let env = AppEnvironment.shared
        env.setup.selfHeal()
        env.updates.start()

        let s = env.setup
        if s.status == .notInstalled {
            OnboardingWindow.show(step: .welcome)
        } else if !s.onboardingCompleted {
            // Someone who was already set up (for example from the command line) should not see the wizard.
            if s.connectedAgents.isEmpty && !s.installedAgents.isEmpty {
                OnboardingWindow.show(step: .connect)
            } else {
                s.onboardingCompleted = true
            }
        }
    }
}

enum OnboardingWindow {
    private static var window: NSWindow?

    static func show(step: OnboardingStep) {
        let env = AppEnvironment.shared
        env.setup.refresh()
        let view = OnboardingView(setup: env.setup, activity: env.activity, previewer: env.previewer,
                                  store: env.store, start: step) { close() }
        let host = NSHostingView(rootView: view)

        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 700),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.isMovableByWindowBackground = true
            window = w
        }
        window?.contentView = host
        window?.center()
        // Since macOS 14 activation is only a request, and this app has no Dock icon, so a window
        // opened at launch can land behind everything. Order it to the front explicitly.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    static func close() {
        SetupModel.shared.onboardingCompleted = true
        window?.close()
    }
}

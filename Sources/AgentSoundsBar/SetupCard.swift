import SwiftUI
import AppKit

// MARK: - Popover setup card

/// Shown at the top of the popover while something still needs doing.
struct SetupCard: View {
    let setup: SetupModel

    private enum Need {
        case install, connect, reconnect([AgentWiring])
    }

    private var need: Need? {
        if setup.status == .notInstalled { return .install }
        if !setup.driftedAgents.isEmpty { return .reconnect(setup.driftedAgents) }
        if setup.connectedAgents.isEmpty && !setup.installedAgents.isEmpty { return .connect }
        return nil
    }

    var body: some View {
        if let need {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: icon(need))
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(LinearGradient(colors: [Color.orange, Color.pink.opacity(0.8)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(need)).font(.system(size: 14, weight: .semibold))
                    Text(detail(need))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Button(action: { act(need) }) {
                    Text(button(need))
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .glassCapsule(tint: Color.orange.opacity(0.55))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(button(need))
            }
            .padding(12)
            .glassCard(radius: 20, tint: Color.orange.opacity(0.18))
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }

    private func icon(_ n: Need) -> String {
        switch n {
        case .install: return "wand.and.stars"
        case .connect: return "link.badge.plus"
        case .reconnect: return "arrow.triangle.2.circlepath"
        }
    }

    private func title(_ n: Need) -> String {
        switch n {
        case .install: return "Finish setup"
        case .connect: return "Connect your agents"
        case .reconnect(let a): return "\(a.map(\.spec.name).joined(separator: ", ")) was reset"
        }
    }

    private func detail(_ n: Need) -> String {
        switch n {
        case .install: return "Nothing is installed yet, so no sounds will play."
        case .connect: return "Your agents are not using Agent Sounds yet."
        case .reconnect: return "Another tool changed its hooks."
        }
    }

    private func button(_ n: Need) -> String {
        switch n {
        case .install: return "Set up"
        case .connect: return "Connect"
        case .reconnect: return "Reconnect"
        }
    }

    private func act(_ n: Need) {
        switch n {
        case .install: OnboardingWindow.show(step: .welcome)
        case .connect: OnboardingWindow.show(step: .connect)
        case .reconnect(let agents): agents.forEach { setup.connect($0.spec) }
        }
    }
}

// MARK: - Agent card (wizard and Agents tab)

struct AgentCard: View {
    let wiring: AgentWiring
    let setup: SetupModel
    @State private var showChanges = false

    private var spec: AgentSpec { wiring.spec }
    private var preview: ConnectPreview? { setup.previews[spec.id] }
    private var canWrite: Bool { setup.status != .notInstalled }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: spec.id == "claude" ? "sparkle" : "terminal.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(spec.name).font(.system(size: 15, weight: .semibold))
                    Text(spec.file.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                badge
            }

            switch wiring.state {
            case .notInstalled:
                Text("Not installed on this Mac, so there is nothing to connect.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            default:
                hookRows
                if let p = preview { previewBlock(p) }
                actions
            }
        }
        .padding(14)
        .glassCard(radius: 20)
    }

    private var badge: some View {
        let (text, color): (String, Color) = {
            switch wiring.state {
            case .connected: return ("Connected", Color(red: 0.6, green: 0.95, blue: 0.6))
            case .drifted: return ("Needs reconnect", .orange)
            case .notConnected: return ("Not connected", .white.opacity(0.6))
            case .notInstalled: return ("Not installed", .white.opacity(0.45))
            }
        }()
        return Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(color.opacity(0.16), in: Capsule())
    }

    private var hookRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(wiring.hooks) { h in
                HStack(spacing: 8) {
                    Image(systemName: icon(h.status)).foregroundStyle(color(h.status)).frame(width: 16)
                    Text(h.hook).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(h.status.label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    private func previewBlock(_ p: ConnectPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let e = p.error {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            } else if p.summary != "Already up to date" || wiring.state != .connected {
                Text(p.summary).font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
                if !p.items.isEmpty {
                    Button(showChanges ? "Hide exact changes" : "Show exact changes") {
                        withAnimation(.smooth) { showChanges.toggle() }
                    }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(.cyan)
                    .accessibilityLabel(showChanges ? "Hide exact changes" : "Show exact changes")
                    if showChanges {
                        ScrollView([.vertical, .horizontal]) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(p.items, id: \.self) { line in
                                    Text(line).font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.85)).textSelection(.enabled)
                                }
                            }
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            ForEach(p.warnings, id: \.self) { w in
                Label(w, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                switch wiring.state {
                case .connected:
                    Button("Disconnect") { setup.disconnect(spec) }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 6).glassCapsule()
                        .accessibilityLabel("Disconnect \(spec.name)")
                case .drifted, .notConnected:
                    Button(wiring.state == .drifted ? "Reconnect" : "Connect") { setup.connect(spec) }
                        .buttonStyle(PrimaryButtonStyle()).disabled(!canWrite || preview?.error != nil)
                        .accessibilityLabel("\(wiring.state == .drifted ? "Reconnect" : "Connect") \(spec.name)")
                default:
                    EmptyView()
                }
                if !canWrite {
                    Text("Install first").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
            }
            if let backup = setup.lastBackup[spec.id] {
                Text("Backup saved: \((backup as NSString).lastPathComponent)")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            }
            if spec.id == "codex", wiring.state == .connected || setup.lastBackup[spec.id] != nil {
                Text("Codex pins each hook it trusts. The first time it runs after a change it may ask you to approve the updated hooks.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func icon(_ s: WireStatus) -> String {
        switch s {
        case .controlled: return "checkmark.circle.fill"
        case .legacy: return "exclamationmark.triangle.fill"
        case .absent: return "circle.dashed"
        }
    }

    private func color(_ s: WireStatus) -> Color {
        switch s {
        case .controlled: return Color(red: 0.6, green: 0.95, blue: 0.6)
        case .legacy: return .orange
        case .absent: return .white.opacity(0.4)
        }
    }
}

// MARK: - Other agents

/// Copy-paste commands for any agent whose hooks we do not write ourselves.
struct OtherAgentsView: View {
    @State private var expanded = false
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.smooth) { expanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0))
                        .font(.system(size: 10, weight: .bold))
                    Text("Other agents (Gemini, Cursor, opencode...)").font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Other agents")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")

            if expanded {
                Text("Run these commands from the matching hook in your agent's settings. Each agent has its own hook format, so check its docs. For stop, the hook's JSON must reach the command on stdin.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                ForEach(SoundEvent.all.filter { $0.key != "stop_error" }) { e in
                    let cmd = "\(Paths.cli.path) \(e.key)"
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.title).font(.system(size: 12, weight: .medium))
                            Text(cmd).font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.55)).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button(copied == e.key ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cmd, forType: .string)
                            copied = e.key
                        }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5).glassCapsule()
                        .accessibilityLabel("Copy command for \(e.title)")
                    }
                }
            }
        }
        .padding(14)
        .glassCard(radius: 20)
    }
}

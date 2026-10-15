import SwiftUI
import ServiceManagement

enum OnboardingStep: Int, CaseIterable {
    case welcome, install, connect, test, done
}

/// First-run wizard: install, connect agents, hear it work.
struct OnboardingView: View {
    let setup: SetupModel
    let activity: ActivityStore
    let previewer: Previewer
    let store: ConfigStore
    let finish: () -> Void

    @State private var step: OnboardingStep
    @State private var revealed = 0
    @State private var installing = false
    @State private var testStart = Date()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var forward = true
    @State private var sealBounce = false

    init(setup: SetupModel, activity: ActivityStore, previewer: Previewer, store: ConfigStore,
         start: OnboardingStep, finish: @escaping () -> Void) {
        self.setup = setup
        self.activity = activity
        self.previewer = previewer
        self.store = store
        self.finish = finish
        _step = State(initialValue: start)
    }

    private var installOK: Bool {
        !setup.installResults.isEmpty && setup.installResults.allSatisfy(\.ok) && revealed >= setup.installResults.count
    }

    var body: some View {
        VStack(spacing: 0) {
            progress.padding(.top, 38).padding(.bottom, 8)
            Group {
                switch step {
                case .welcome: welcome
                case .install: install
                case .connect: connect
                case .test: test
                case .done: done
                }
            }
            .id(step)
            .transition(.asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .padding(.horizontal, 28)
        .frame(width: 580, height: 700)
        .background { AuroraBackground(muted: false, playing: activity.isAnimating) }
        .environment(\.colorScheme, .dark)
        .focusEffectDisabled()
        .task(id: step) {
            if step == .install, !installing { await runInstall() }
            if step == .test { testStart = Date() }
        }
    }

    // MARK: Chrome

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Color.white : Color.white.opacity(0.2))
                    .frame(width: s == step ? 28 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: step)
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") { go(to: OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome, forward: false) }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 16).padding(.vertical, 9).glassCapsule()
                    .disabled(installing)
                    .accessibilityLabel("Back")
            }
            Spacer()
            Button(primaryTitle) { next() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(step == .install && !installOK)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(primaryTitle)
        }
        .padding(.vertical, 22)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "Get started"
        case .install: return "Continue"
        case .connect: return setup.connectedAgents.isEmpty ? "Skip for now" : "Continue"
        case .test: return "Continue"
        case .done: return "Finish"
        }
    }

    private func next() {
        if step == .done { finish(); return }
        go(to: OnboardingStep(rawValue: step.rawValue + 1) ?? .done, forward: true)
    }

    private func go(to s: OnboardingStep, forward f: Bool) {
        forward = f
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { step = s }
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 10).padding(.bottom, 16)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            Waveform(activity: activity, muted: false, level: 1, bars: 9, height: 96)
                .padding(.horizontal, 36).padding(.vertical, 28)
                .glassCard(radius: 34, tint: Color.purple.opacity(0.3))
            heading("Sounds for your coding agents",
                    "Hear when Claude Code, Codex and other agents start, finish, or need you, and control the volume from the menu bar.")
            VStack(alignment: .leading, spacing: 12) {
                feature("slider.horizontal.3", "One volume and mute for every agent")
                feature("music.note.list", "A different sound for each event")
                feature("link", "Set up in under a minute, and undo it any time")
            }
            Spacer()
        }
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 30, height: 30)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(text).font(.system(size: 14, weight: .medium))
        }
    }

    private var install: some View {
        VStack(spacing: 0) {
            heading("Setting things up", "Installing the pieces your agents' hooks need.")
            VStack(spacing: 0) {
                if setup.installResults.isEmpty {
                    HStack { ProgressView().controlSize(.small); Text("Starting...").font(.system(size: 13)) }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
                ForEach(Array(setup.installResults.enumerated()), id: \.element.id) { i, r in
                    HStack(alignment: .top, spacing: 12) {
                        Group {
                            if i < revealed {
                                Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                    .foregroundStyle(r.ok ? Color(red: 0.6, green: 0.95, blue: 0.6) : .red)
                                    .symbolEffect(.bounce, value: revealed)
                            } else {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.system(size: 13, weight: .semibold))
                            if i < revealed {
                                Text(r.detail).font(.system(size: 11))
                                    .foregroundStyle(r.ok ? Color.white.opacity(0.55) : .red.opacity(0.9))
                                    .lineLimit(3)
                            }
                        }
                        Spacer()
                    }
                    .padding(14)
                    if i < setup.installResults.count - 1 { Divider().opacity(0.3) }
                }
            }
            .glassCard(radius: 20)

            if !installing, !setup.installResults.isEmpty, !setup.installResults.allSatisfy(\.ok) {
                Button("Try again") { Task { await runInstall() } }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 18).padding(.vertical, 9).glassCapsule().padding(.top, 16)
                    .accessibilityLabel("Try the installation again")
            }
            Spacer()
        }
    }

    private func runInstall() async {
        installing = true
        revealed = 0
        try? await Task.sleep(nanoseconds: 350_000_000)
        setup.runInstall()
        for i in 1...max(setup.installResults.count, 1) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { revealed = i }
            try? await Task.sleep(nanoseconds: 280_000_000)
        }
        installing = false
    }

    private var connect: some View {
        VStack(spacing: 0) {
            heading("Connect your agents",
                    "Agent Sounds adds a small hook to each agent. You see exactly what changes, and a backup is saved first.")
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(setup.agents) { AgentCard(wiring: $0, setup: setup) }
                    OtherAgentsView()
                    if let m = setup.message {
                        Text(m).font(.system(size: 11)).foregroundStyle(.red)
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { setup.refresh() }
    }

    private var test: some View {
        VStack(spacing: 0) {
            heading("Try it", "Preview the sounds, then use an agent and watch it show up here.")
            VStack(alignment: .leading, spacing: 10) {
                Text("Preview").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                FlowChips(events: SoundEvent.all) { e in
                    let s = store.config.events[e.key] ?? EventSetting(enabled: true, sound: e.defaultSound)
                    previewer.play(sound: s.sound, volume: store.config.volume)
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).glassCard(radius: 20)

            VStack(alignment: .leading, spacing: 12) {
                Text("Waiting for your agents").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                if setup.connectedAgents.isEmpty {
                    Text("No agents are connected yet. Go back to connect one.")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }
                ForEach(setup.connectedAgents) { w in
                    let heard = activity.entries.contains { $0.agent == w.spec.id && $0.date >= testStart.addingTimeInterval(-1) }
                    HStack(spacing: 10) {
                        if heard {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(red: 0.6, green: 0.95, blue: 0.6))
                                .symbolEffect(.bounce, value: heard)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(heard ? "Heard from \(w.spec.name)" : "Send a prompt in \(w.spec.name)")
                                .font(.system(size: 13, weight: .semibold))
                            if !heard { stuckHint(w.spec) }
                        }
                        Spacer()
                    }
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).glassCard(radius: 20).padding(.top, 12)
            Spacer()
        }
    }

    /// Appears only after 25 seconds without an event.
    private func stuckHint(_ spec: AgentSpec) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            if tl.date.timeIntervalSince(testStart) > 25 {
                Text(spec.id == "codex"
                     ? "Nothing yet. Codex may be asking you to approve the changed hooks, or this version may need hooks turned on in its settings."
                     : "Nothing yet. Start a new session, since running sessions may not pick up changed hooks.")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var done: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(LinearGradient(colors: [Color(red: 0.6, green: 1.0, blue: 0.8), Color(red: 0.5, green: 0.7, blue: 1.0)],
                                                startPoint: .top, endPoint: .bottom))
                .symbolEffect(.bounce, value: sealBounce)
                .onAppear { sealBounce = true }
            heading("You're all set", "Agent Sounds lives in your menu bar.")
            VStack(alignment: .leading, spacing: 14) {
                feature("waveform", "Look for the equalizer icon. It dances when a sound plays.")
                feature("eye.slash", "Can't see it? A menu bar manager may be hiding it.")
                HStack {
                    feature("power", "Start Agent Sounds when you log in")
                    Spacer()
                    GlassSwitch(isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin), tint: .mint,
                                label: "Start Agent Sounds at login")
                }
            }
            .padding(16).glassCard(radius: 20)
            Spacer()
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {}
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// Wrapping row of small play buttons, one per event.
private struct FlowChips: View {
    let events: [SoundEvent]
    let play: (SoundEvent) -> Void
    @State private var bounced: String?

    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 120), spacing: 8)]
        LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
            ForEach(events) { e in
                Button { bounced = e.key; play(e) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: e.symbol).symbolEffect(.bounce, value: bounced == e.key)
                        Text(e.title).lineLimit(1)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .glassCapsule(tint: e.accent.opacity(0.25))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Preview \(e.title) sound")
            }
        }
    }
}

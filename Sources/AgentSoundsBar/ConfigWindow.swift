import SwiftUI
import AppKit

/// A read-mostly explainer of the whole setup: how a hook becomes a sound, what each
/// event does, which agents are wired, and what just happened.
struct ConfigWindow: View {
    let store: ConfigStore
    let activity: ActivityStore
    let previewer: Previewer
    let setup: SetupModel
    @Bindable var updates: UpdateChecker

    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview", events = "Events", agents = "Agents", activity = "Activity"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .overview
    @State private var soundCount = SoundLibrary.available().count

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                Group {
                    switch tab {
                    case .overview: overview
                    case .events: events
                    case .agents: agents
                    case .activity: activityTab
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .frame(minWidth: 700, minHeight: 540)
        .background { AuroraBackground(muted: store.config.muted, playing: activity.isAnimating) }
        .environment(\.colorScheme, .dark)
        .focusEffectDisabled()
        .onAppear(perform: rescan)
        .onChange(of: tab) { _, _ in rescan() }
    }

    private func rescan() {
        setup.refresh()
        soundCount = SoundLibrary.available().count
    }

    // MARK: Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("How it works") {
                HStack(alignment: .top, spacing: 8) {
                    flowStep("1", "Agent hook", "Claude Code or Codex fires an event such as Stop.")
                    arrow
                    flowStep("2", "play-sound", "The hook runs play-sound <event> instead of afplay.")
                    arrow
                    flowStep("3", "config.json", "It reads mute, volume and the sound chosen for that event.")
                    arrow
                    flowStep("4", "afplay", "It plays the sound at that volume and logs what happened.")
                }
                Text("This app only edits config.json. The hooks read it every time, so sounds keep working when the app is closed, and any other agent can join by running play-sound from its hook.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            section("Current settings") {
                let c = store.config
                row("Master volume", "\(Int((c.volume * 100).rounded()))%")
                row("Mute", c.muted ? "On: nothing plays" : "Off")
                row("Events enabled", "\(c.events.values.filter(\.enabled).count) of \(SoundEvent.all.count)")
                row("Sounds available", "\(soundCount) file\(soundCount == 1 ? "" : "s")")
            }

            section("Health") {
                check(setup.status != .notInstalled,
                      "play-sound is installed", "Open the setup guide from the menu bar gear.")
                check(setup.jqPath != nil, "jq is available",
                      "play-sound needs jq. macOS 15 and later include it; on older versions run: brew install jq")
                check(FileManager.default.fileExists(atPath: Paths.config.path),
                      "config.json exists", "The app creates it on launch.")
                check(store.lastError == nil, "config.json is valid", store.lastError ?? "")
                ForEach(setup.installedAgents) { w in
                    check(w.state == .connected,
                          "\(w.spec.name) sounds are controlled by this app",
                          w.state == .drifted ? "Its hooks were changed. Reconnect it in the Agents tab."
                                              : "Connect it in the Agents tab.")
                }
                if setup.installedAgents.isEmpty {
                    check(false, "A supported agent is installed", "Claude Code or Codex were not found on this Mac.")
                }
            }

            section("Updates") {
                row("Version", updates.current?.description ?? "dev build")
                row("Installed with", updates.source.title)
                HStack {
                    Text("Channel").foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
                    Picker("", selection: $updates.channel) {
                        ForEach(UpdateChannel.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                    Text(updates.channel.detail).font(.caption).foregroundStyle(.secondary)
                }
                row("Last checked", updates.lastChecked.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not yet")
                HStack(spacing: 12) {
                    if let r = updates.available {
                        Button(updates.upgradesInPlace(r) ? "Update to \(r.tagName)" : "Download \(r.tagName)") { updates.install() }
                        Link("Release notes", destination: r.htmlURL)
                    } else {
                        Button("Check for Updates") { updates.check(manual: true) }
                            .disabled(updates.state == .checking)
                    }
                    Toggle("Check automatically", isOn: $updates.automatic)
                    if case .failed(let m) = updates.state { Text(m).font(.caption).foregroundStyle(.orange) }
                    if case .upToDate = updates.state { Text("Up to date").font(.caption).foregroundStyle(.secondary) }
                }
            }

            section("Files") {
                fileRow("Config", Paths.config, "Mute, volume and the sound for each event. Safe to edit by hand.")
                fileRow("Sounds", Paths.sounds, "Drop .wav .mp3 .aiff .m4a or .caf files here to make them selectable.")
                fileRow("play-sound", Paths.cli, "The command every hook runs.")
                fileRow("History", Paths.history, "One line per hook call. Powers the icon animation and the Activity tab.")
            }
        }
    }

    private var arrow: some View {
        Image(systemName: "chevron.right").foregroundStyle(.tertiary).padding(.top, 18)
    }

    private func flowStep(_ n: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(n).font(.caption.bold()).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassCard(radius: 14)
    }

    // MARK: Events

    private var events: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Each row is one thing an agent can tell you. Change the sound or turn it off here or in the menu bar popover.")
                .foregroundStyle(.secondary)
            ForEach(SoundEvent.all) { event in
                let s = store.config.events[event.key]
                    ?? EventSetting(enabled: true, sound: event.defaultSound)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(event.title).font(.headline)
                        Text(event.key).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Spacer()
                        Text(s.enabled ? "On" : "Off")
                            .font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background((s.enabled ? Color.green : Color.gray).opacity(0.2), in: Capsule())
                    }
                    Text(event.explanation).font(.callout)
                    HStack(spacing: 16) {
                        Label("Hook: \(event.hook)", systemImage: "link")
                        Label(SoundLibrary.display(s.sound), systemImage: "music.note")
                        Button { previewer.play(sound: s.sound, volume: store.config.volume) } label: {
                            Label("Preview", systemImage: "play.fill")
                        }
                        .buttonStyle(.link)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .glassCard(radius: 16)
            }
        }
    }

    // MARK: Agents

    private var agents: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect adds a small hook to an agent so its sounds follow your volume and mute. Disconnect removes it again. A backup of the agent's file is saved beside it before every change.")
                .foregroundStyle(.secondary)
            ForEach(setup.agents) { AgentCard(wiring: $0, setup: setup) }
            OtherAgentsView()
            if let m = setup.message { Text(m).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Rescan", action: rescan)
                Button("Run setup guide again") { OnboardingWindow.show(step: .welcome) }
            }
        }
    }

    // MARK: Activity

    private var activityTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Every time a hook calls play-sound it is logged here, including the times nothing played and why.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { activity.clear() }.disabled(activity.entries.isEmpty)
            }
            if activity.entries.isEmpty {
                Text("Nothing yet. Send a prompt in Claude Code or Codex, or press a Preview button, and the next hook call will show up here.")
                    .padding(.vertical, 30)
            } else {
                ForEach(activity.entries) { e in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: e.playedSound ? "speaker.wave.2.fill" : "speaker.slash")
                            .foregroundStyle(e.playedSound ? Color.green : Color.orange)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(SoundEvent.title(for: e.event)).font(.body.weight(.medium))
                            Text(e.explanation).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        RelativeTime(date: e.date).font(.caption).foregroundStyle(.tertiary)
                    }
                    Divider()
                }
            }
        }
    }

    // MARK: Small pieces

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.bold())
            content()
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary).frame(width: 150, alignment: .leading); Text(v) }
    }

    private func check(_ ok: Bool, _ title: String, _ hint: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? Color.green : Color.orange)
            Text(title)
            if !ok && !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func fileRow(_ title: String, _ url: URL, _ detail: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(url.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }
}

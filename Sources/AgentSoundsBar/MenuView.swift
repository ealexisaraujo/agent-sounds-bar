import SwiftUI
import AppKit
import ServiceManagement

struct MenuView: View {
    let store: ConfigStore
    let activity: ActivityStore
    let previewer: Previewer
    let setup: SetupModel
    let updates: UpdateChecker

    @Environment(\.openWindow) private var openWindow
    @State private var sounds: [String] = SoundLibrary.available()
    @State private var draftVolume: Double = 0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var appeared = false

    private var config: SoundConfig { store.config }
    private var silent: Bool { config.muted || config.volume == 0 }

    var body: some View {
        VStack(spacing: 14) {
            header
            SetupCard(setup: setup)
            VStack(spacing: 14) {
                volumeCard
                eventGrid
            }
            .opacity(setup.status == .notInstalled ? 0.4 : 1)
            .allowsHitTesting(setup.status != .notInstalled)
            .animation(.smooth, value: setup.status == .notInstalled)
            UpdateCard(updates: updates)
                .animation(.smooth, value: updates.state)
            footer
        }
        .padding(16)
        .frame(width: 400)
        .background { AuroraBackground(muted: silent, playing: activity.isAnimating) }
        .environment(\.colorScheme, .dark)
        .focusEffectDisabled()
        .onAppear {
            sounds = SoundLibrary.available()
            setup.refresh()
            draftVolume = config.volume
            appeared = false
            withAnimation { appeared = true }
        }
        .onChange(of: config.volume) { _, new in draftVolume = new }
    }

    // MARK: Header

    private var status: (word: String, color: Color) {
        if setup.status == .notInstalled { return ("Not set up", Color(red: 1.0, green: 0.72, blue: 0.35)) }
        if config.muted { return ("Muted", Color(red: 1.0, green: 0.72, blue: 0.35)) }
        if config.volume == 0 { return ("Silent", Color(red: 1.0, green: 0.72, blue: 0.35)) }
        return ("On", Color(red: 0.72, green: 1.0, blue: 0.62))
    }

    private var connection: String {
        if setup.status == .notInstalled { return "Not set up yet" }
        let names: ([AgentWiring]) -> String = { $0.map(\.spec.name).joined(separator: " · ") }
        if !setup.driftedAgents.isEmpty { return names(setup.driftedAgents) + ": hooks need reconnecting" }
        if setup.connectedAgents.isEmpty {
            return setup.installedAgents.isEmpty ? "No supported agent found on this Mac" : "No agents connected yet"
        }
        return names(setup.connectedAgents) + " connected"
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Agent Sounds:").foregroundStyle(.white)
                    Text(status.word)
                        .foregroundStyle(status.color)
                        .contentTransition(.interpolate)
                }
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .animation(.smooth, value: status.word)
                Text(connection)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
            Spacer()
            Waveform(activity: activity, muted: silent, level: config.volume, bars: 5, height: 34)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .glassCard(radius: 22, tint: silent ? nil : Color.purple.opacity(0.35))
        }
        .padding(.horizontal, 4)
    }

    // MARK: Volume

    private var volumeCard: some View {
        let pct = Int((draftVolume * 100).rounded())
        return VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Master volume")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("\(pct)%")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(pct)))
                    .animation(.snappy, value: pct)
            }
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").foregroundStyle(.white.opacity(0.6))
                GlassSlider(value: $draftVolume,
                            colors: [Color(red: 0.45, green: 0.85, blue: 1.0), Color(red: 0.70, green: 0.50, blue: 1.0)]) {
                    store.update { $0.volume = draftVolume }
                    if let stop = config.events["stop"] {
                        previewer.play(sound: stop.sound, volume: draftVolume)
                    }
                }
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.white.opacity(0.6))
            }
            .opacity(config.muted ? 0.4 : 1)
            .allowsHitTesting(!config.muted)
            .animation(.smooth, value: config.muted)

            HStack {
                Button {
                    store.update { $0.muted.toggle() }
                } label: {
                    Label(config.muted ? "Unmute" : "Mute",
                          systemImage: config.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .glassCapsule(tint: config.muted ? Color.orange.opacity(0.5) : nil)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(config.muted ? "Unmute all agent sounds" : "Mute all agent sounds")
                Spacer()
                Text("Applies to every connected agent")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(16)
        .glassCard(radius: 22)
    }

    // MARK: Events

    private var eventGrid: some View {
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow { tile(0); tile(1) }
            GridRow { tile(2); tile(3) }
            GridRow { tile(4); lastActivityCard }
        }
    }

    private func tile(_ index: Int) -> some View {
        EventTile(event: SoundEvent.all[index], store: store, activity: activity,
                  previewer: previewer, sounds: sounds,
                  onSoundsChanged: { sounds = SoundLibrary.available() })
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .scaleEffect(appeared ? 1 : 0.96)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.06), value: appeared)
    }

    private var lastActivityCard: some View {
        let e = activity.entries.first
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill").foregroundStyle(.white.opacity(0.6))
                Text("Last activity").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            if let e {
                Text(SoundEvent.title(for: e.event))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(e.explanation)
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
                Spacer(minLength: 0)
                RelativeTime(date: e.date)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(e.playedSound ? Color(red: 0.72, green: 1.0, blue: 0.62) : .orange)
            } else {
                Text("Nothing yet")
                    .font(.system(size: 14, weight: .semibold))
                Text("Send a prompt in Claude Code or Codex and it shows up here.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(12)
        .glassCard(radius: 20)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut.delay(0.35), value: appeared)
        .animation(.smooth, value: e?.id)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Menu {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                Button("Set up again...") { OnboardingWindow.show(step: .welcome) }
                Divider()
                Button("Open sounds folder") { NSWorkspace.shared.open(Paths.sounds) }
                Button("Show config file") { NSWorkspace.shared.activateFileViewerSelecting([Paths.config]) }
                Divider()
                UpdateMenuItems(updates: updates)
                Text("Version \(updates.current?.description ?? "dev")")
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .glassCircle()
            }
            .menuStyle(.button).buttonStyle(PressableStyle()).menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More options")

            Button {
                openWindow(id: "config")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Text("Open Configuration")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .glassCapsule()
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Open Configuration")

            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .glassCircle()
            }
            .buttonStyle(PressableStyle())
            .keyboardShortcut("q")
            .help("Quit Agent Sounds")
            .accessibilityLabel("Quit Agent Sounds")
        }
        .foregroundStyle(.white)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            // Fails outside a signed .app bundle; the toggle snaps back below.
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Event tile

private struct EventTile: View {
    let event: SoundEvent
    let store: ConfigStore
    let activity: ActivityStore
    let previewer: Previewer
    let sounds: [String]
    let onSoundsChanged: () -> Void

    @State private var hovering = false
    @State private var plays = 0

    private var setting: EventSetting {
        store.config.events[event.key] ?? EventSetting(enabled: true, sound: event.defaultSound)
    }

    private var choices: [String] {
        sounds.contains(setting.sound) ? sounds : [setting.sound] + sounds
    }

    /// True while this event's sound is the one that just played.
    private var glowing: Bool {
        guard activity.isAnimating, let e = activity.entries.first else { return false }
        return e.event == event.key && e.playedSound
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: event.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: glowing)
                    .frame(width: 30, height: 30)
                    .background(
                        LinearGradient(colors: [event.accent, event.accent.opacity(0.55)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .shadow(color: event.accent.opacity(glowing ? 0.9 : 0.35), radius: glowing ? 10 : 4)
                Spacer()
                GlassSwitch(isOn: Binding(
                    get: { setting.enabled },
                    set: { v in store.update { $0.events[event.key] = EventSetting(enabled: v, sound: setting.sound) } }),
                    tint: event.accent, label: "\(event.title) sound")
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(event.detail)
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Menu {
                    if choices.isEmpty { Text("No sounds yet") }
                    let mine = choices.filter { !SoundLibrary.isBuiltIn($0) }
                    let builtIn = choices.filter(SoundLibrary.isBuiltIn)
                    if !mine.isEmpty {
                        Section("Your sounds") { ForEach(mine, id: \.self, content: choice) }
                    }
                    if !builtIn.isEmpty {
                        Section("macOS sounds") { ForEach(builtIn, id: \.self, content: choice) }
                    }
                    Divider()
                    Button("Add sound...") {
                        guard let name = SoundLibrary.addViaPanel() else { return }
                        onSoundsChanged()
                        store.update { $0.events[event.key] = EventSetting(enabled: setting.enabled, sound: name) }
                        previewer.play(sound: name, volume: store.config.volume)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(SoundLibrary.display(setting.sound))
                            .lineLimit(1).truncationMode(.middle)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 7, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.white.opacity(0.12), in: Capsule())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                .disabled(!setting.enabled)

                Spacer(minLength: 0)

                Button {
                    plays += 1
                    previewer.play(sound: setting.sound, volume: store.config.volume)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.14), in: Circle())
                        .symbolEffect(.bounce, value: plays)
                }
                .buttonStyle(PressableStyle())
                .help("Preview")
                .accessibilityLabel("Preview \(event.title) sound")
            }
        }
        .padding(12)
        .glassCard(radius: 20, tint: event.accent.opacity(glowing ? 0.4 : (setting.enabled ? 0.10 : 0)))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(event.accent.opacity(glowing ? 0.9 : 0), lineWidth: 1.5)
        }
        .opacity(setting.enabled ? 1 : 0.55)
        .scaleEffect(glowing ? 1.03 : (hovering ? 1.02 : 1))
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: hovering)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: glowing)
        .animation(.smooth, value: setting.enabled)
    }

    private func choice(_ name: String) -> some View {
        Button {
            store.update { $0.events[event.key] = EventSetting(enabled: setting.enabled, sound: name) }
            previewer.play(sound: name, volume: store.config.volume)
        } label: {
            if name == setting.sound {
                Label(SoundLibrary.display(name), systemImage: "checkmark")
            } else {
                Text(SoundLibrary.display(name))
            }
        }
    }
}

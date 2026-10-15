import SwiftUI

// MARK: - Per-event look

extension SoundEvent {
    var symbol: String {
        switch key {
        case "session_start": return "power"
        case "user_prompt_submit": return "paperplane.fill"
        case "stop": return "checkmark.seal.fill"
        case "stop_error": return "exclamationmark.triangle.fill"
        default: return "bell.badge.fill"
        }
    }

    var accent: Color {
        switch key {
        case "session_start": return Color(red: 0.36, green: 0.78, blue: 1.0)
        case "user_prompt_submit": return Color(red: 0.42, green: 0.92, blue: 0.72)
        case "stop": return Color(red: 0.55, green: 0.86, blue: 0.40)
        case "stop_error": return Color(red: 1.0, green: 0.62, blue: 0.30)
        default: return Color(red: 0.95, green: 0.50, blue: 0.85)
        }
    }
}

// MARK: - Liquid Glass with a material fallback

extension View {
    /// Liquid Glass on macOS 26, a translucent material before that.
    @ViewBuilder
    func glassCard(radius: CGFloat = 20, tint: Color? = nil, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(Self.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .background(tint?.opacity(0.18) ?? .clear, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 0.6))
        }
    }

    @available(macOS 26.0, *)
    private static func glass(tint: Color?, interactive: Bool) -> Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }

    @ViewBuilder
    func glassCircle(tint: Color? = nil, interactive: Bool = true) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(Self.glass(tint: tint, interactive: interactive), in: Circle())
        } else {
            self.background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.6))
        }
    }

    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = true) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(Self.glass(tint: tint, interactive: interactive), in: Capsule())
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
                .background(tint?.opacity(0.2) ?? .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.6))
        }
    }
}

/// Spring press feedback for plain buttons.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Aurora background

/// Slowly drifting colour blobs behind the glass. Calms down and desaturates when
/// muted, and swells briefly when a sound plays.
struct AuroraBackground: View {
    var muted: Bool
    var playing: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                LinearGradient(
                    colors: muted
                        ? [Color(red: 0.10, green: 0.10, blue: 0.14), Color(red: 0.04, green: 0.04, blue: 0.07)]
                        : [Color(red: 0.13, green: 0.05, blue: 0.32), Color(red: 0.04, green: 0.02, blue: 0.14)],
                    startPoint: .top, endPoint: .bottom)
                blob(muted ? .gray : Color(red: 0.55, green: 0.25, blue: 1.0), size: 300,
                     x: cos(t * 0.23) * 110, y: sin(t * 0.19) * 90 - 160, t: t)
                blob(muted ? .gray : Color(red: 0.20, green: 0.45, blue: 1.0), size: 260,
                     x: cos(t * 0.17 + 2) * 120, y: sin(t * 0.21 + 1) * 110 + 60, t: t)
                blob(muted ? .gray : Color(red: 0.95, green: 0.35, blue: 0.80), size: 220,
                     x: cos(t * 0.20 + 4) * 100, y: sin(t * 0.15 + 3) * 90 + 240, t: t)
            }
            .animation(.easeInOut(duration: 0.8), value: muted)
        }
        .clipped()
        .overlay(Color.white.opacity(playing ? 0.05 : 0).animation(.easeOut(duration: 0.4), value: playing))
    }

    private func blob(_ color: Color, size: CGFloat, x: Double, y: Double, t: Double) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: 70)
            .opacity((muted ? 0.16 : 0.55) + (playing ? 0.15 : 0))
            .offset(x: x, y: y)
    }
}

// MARK: - Controls

/// Capsule slider with a glowing gradient fill and a springy knob.
struct GlassSlider: View {
    @Binding var value: Double
    var colors: [Color]
    var onCommit: () -> Void

    @State private var dragging = false

    var body: some View {
        GeometryReader { g in
            let knob: CGFloat = 28
            let usable = max(g.size.width - knob, 1)
            let x = knob / 2 + usable * value
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12)).frame(height: 12)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(x, 12), height: 12)
                    .shadow(color: colors.last?.opacity(dragging ? 0.8 : 0.45) ?? .clear, radius: dragging ? 10 : 6)
                Circle()
                    .fill(.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                    .scaleEffect(dragging ? 1.15 : 1)
                    .offset(x: x - knob / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragging = true
                        value = min(max((v.location.x - knob / 2) / usable, 0), 1)
                    }
                    .onEnded { _ in
                        dragging = false
                        onCommit()
                    })
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: dragging)
        }
        .frame(height: 30)
    }
}

/// Small iOS-style switch with a spring.
struct GlassSwitch: View {
    @Binding var isOn: Bool
    var tint: Color
    var label = "Toggle"

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? tint.opacity(0.85) : Color.white.opacity(0.18))
                    .frame(width: 36, height: 22)
                Circle().fill(.white).frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .padding(2)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// Equalizer bars that breathe at rest and dance while a sound plays.
struct Waveform: View {
    let activity: ActivityStore
    var muted: Bool
    var level: Double
    var bars = 7
    var height: CGFloat = 56
    var colors: [Color] = [Color(red: 0.55, green: 0.95, blue: 0.95), Color(red: 0.75, green: 0.55, blue: 1.0)]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: height * 0.09) {
                ForEach(0..<bars, id: \.self) { i in
                    let k = Double(i)
                    let amp: Double = activity.isAnimating
                        ? 0.3 + 0.7 * abs(sin(activity.phase * (1 + 0.13 * k) + k * 0.9))
                        : 0.22 + 0.1 * sin(t * 1.5 + k * 0.8)
                    let scale = muted ? 0.2 : 0.5 + 0.5 * level
                    Capsule()
                        .fill(LinearGradient(colors: muted ? [.gray, .gray.opacity(0.6)] : colors,
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: height * 0.11, height: max(height * 0.11, height * amp * scale))
                }
            }
            .frame(height: height)
        }
    }
}

/// "just now", "2 min. ago": compact and live, unlike Text(date, style: .relative).
struct RelativeTime: View {
    let date: Date
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { tl in
            Text(tl.date.timeIntervalSince(date) < 5
                 ? "just now"
                 : Self.formatter.localizedString(for: date, relativeTo: tl.date))
        }
    }
}

/// Filled gradient button for the main action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryLabel(configuration: configuration)
    }

    private struct PrimaryLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22).padding(.vertical, 10)
                .background(
                    LinearGradient(colors: [Color(red: 0.40, green: 0.58, blue: 1.0), Color(red: 0.70, green: 0.40, blue: 1.0)],
                                   startPoint: .leading, endPoint: .trailing),
                    in: Capsule())
                .shadow(color: Color.purple.opacity(enabled ? 0.5 : 0), radius: configuration.isPressed ? 4 : 10, y: 3)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(enabled ? 1 : 0.4)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
        }
    }
}

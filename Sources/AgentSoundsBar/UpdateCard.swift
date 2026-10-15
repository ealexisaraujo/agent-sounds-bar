import SwiftUI
import AppKit

/// Shown in the popover when an update is available, being installed, or a check the user asked for
/// has something to say. Hidden otherwise.
struct UpdateCard: View {
    let updates: UpdateChecker

    private struct Content {
        var icon: String
        var title: String
        var detail: String
        var button: String?
        var busy = false
    }

    private var content: Content? {
        switch updates.state {
        case .available(let r):
            let how = updates.upgradesInPlace(r) ? "Update" : "Download"
            let mine = updates.current.map { " · you have \($0)" } ?? ""
            return Content(icon: "arrow.down.circle.fill",
                           title: r.prerelease ? "Beta update available" : "Update available",
                           detail: "Version \(r.version?.description ?? r.tagName)\(mine)",
                           button: how)
        case .installing(let step):
            return Content(icon: "arrow.triangle.2.circlepath", title: step,
                           detail: "The app restarts when it's done.", busy: true)
        case .checking where updates.manual:
            return Content(icon: "arrow.triangle.2.circlepath", title: "Checking for updates...",
                           detail: "\(updates.channel.title) channel", busy: true)
        case .upToDate where updates.manual:
            return Content(icon: "checkmark.circle.fill", title: "You're up to date",
                           detail: "Version \(updates.current?.description ?? "?") · \(updates.channel.title) channel")
        case .failed(let message):
            return Content(icon: "exclamationmark.triangle.fill", title: "Update failed", detail: message,
                           button: "Retry")
        default:
            return nil
        }
    }

    var body: some View {
        if let c = content {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: c.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .symbolEffect(.pulse, isActive: c.busy)
                    .frame(width: 40, height: 40)
                    .background(LinearGradient(colors: [Color.pink, Color.purple.opacity(0.85)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(c.detail)
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                if let label = c.button {
                    Button {
                        if case .failed = updates.state { updates.check(manual: true) } else { updates.install() }
                    } label: {
                        Text(label)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .glassCapsule(tint: Color.purple.opacity(0.55))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(label == "Retry" ? "Retry the update check" : "\(label) the new version")
                }
                if !c.busy {
                    Button { updates.dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 22, height: 22)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Dismiss")
                }
            }
            .padding(12)
            .glassCard(radius: 20, tint: Color.purple.opacity(0.18))
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }
}

/// The update controls shared by the popover's gear menu.
struct UpdateMenuItems: View {
    @Bindable var updates: UpdateChecker

    var body: some View {
        if let r = updates.available {
            let v = r.version?.description ?? r.tagName
            Button(updates.upgradesInPlace(r) ? "Update to \(v)..." : "Download \(v)...") { updates.install() }
        } else {
            Button("Check for Updates...") { updates.check(manual: true) }
        }
        Picker("Update channel", selection: $updates.channel) {
            ForEach(UpdateChannel.allCases) { Text($0.title).tag($0) }
        }
        Toggle("Check for updates automatically", isOn: $updates.automatic)
    }
}

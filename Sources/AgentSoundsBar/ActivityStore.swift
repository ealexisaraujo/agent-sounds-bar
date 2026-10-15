import Foundation
import AppKit
import Observation

struct ActivityEntry: Identifiable {
    let id: Int
    let date: Date
    let event: String
    let result: String
    let sound: String
    let agent: String

    var playedSound: Bool { result == "played" }

    /// Plain-language reason, so a silent hook is never a mystery.
    var explanation: String {
        switch result {
        case "played": return "Played \(SoundLibrary.display(sound))"
        case "muted": return "Skipped: mute is on"
        case "disabled": return "Skipped: this event is turned off"
        case "zero_volume": return "Skipped: volume is 0%"
        case "missing_file": return "Skipped: sound file not found (\(sound))"
        default: return result
        }
    }
}

/// Watches the history log that `play-sound` appends to. Drives the icon animation
/// and the Activity tab.
@Observable
final class ActivityStore {
    private(set) var entries: [ActivityEntry] = []   // newest first
    private(set) var phase: Double = 0
    private(set) var isAnimating = false

    @ObservationIgnored private var lastLines: [String] = []
    @ObservationIgnored private var lastStamp: (Date?, Int)?
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var animTimer: Timer?
    @ObservationIgnored private var animUntil = Date.distantPast

    init() {
        refresh(initial: true)
        // The log is appended to, which doesn't fire directory events, so poll cheaply.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.refresh(initial: false)
        }
    }

    deinit {
        pollTimer?.invalidate()
        animTimer?.invalidate()
    }

    func clear() {
        try? FileManager.default.removeItem(at: Paths.history)
        refresh(initial: true)
    }

    private func refresh(initial: Bool) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: Paths.history.path)
        let stamp = (attrs?[.modificationDate] as? Date, (attrs?[.size] as? Int) ?? -1)
        if let last = lastStamp, last.0 == stamp.0, last.1 == stamp.1 { return }
        lastStamp = stamp

        guard let text = try? String(contentsOf: Paths.history, encoding: .utf8) else {
            entries = []
            lastLines = []
            return
        }
        let lines = text.split(separator: "\n").map(String.init)
        var fresh = lines[...]
        if let last = lastLines.last, let idx = lines.lastIndex(of: last) {
            fresh = lines[(idx + 1)...]
        }
        lastLines = lines

        let parsed = lines.enumerated().compactMap { Self.parse($1, id: $0) }
        entries = Array(parsed.suffix(100).reversed())

        guard !initial else { return }
        let recent = Date().addingTimeInterval(-5)
        let shouldAnimate = fresh.enumerated().contains { offset, line in
            guard let e = Self.parse(line, id: offset) else { return false }
            return e.playedSound && e.date > recent
        }
        if shouldAnimate { trigger() }
    }

    private static func parse(_ line: String, id: Int) -> ActivityEntry? {
        let f = line.components(separatedBy: "\t")
        guard f.count >= 3, let epoch = TimeInterval(f[0]) else { return nil }
        return ActivityEntry(id: id, date: Date(timeIntervalSince1970: epoch),
                             event: f[1], result: f[2], sound: f.count > 3 ? f[3] : "",
                             agent: f.count > 4 ? f[4] : "")
    }

    private func trigger() {
        animUntil = Date().addingTimeInterval(1.6)
        isAnimating = true
        guard animTimer == nil else { return }
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.phase += 0.45
            if Date() > self.animUntil {
                t.invalidate()
                self.animTimer = nil
                self.isAnimating = false
            }
        }
    }
}

/// Menu bar icon: four equalizer bars. They rest at a height that follows the
/// volume, dance while a sound plays, and go flat with a slash when muted.
enum EqualizerIcon {
    static func image(animating: Bool, phase: Double, muted: Bool, level: Double) -> NSImage {
        let size = NSSize(width: 20, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            let barW: CGFloat = 2.6, gap: CGFloat = 2.2
            let rest: [CGFloat] = [6, 11, 8, 5]
            let scale = 0.55 + 0.45 * CGFloat(level)
            var x = (rect.width - (4 * barW + 3 * gap)) / 2

            NSColor.black.setFill()
            for i in 0..<4 {
                var h: CGFloat
                if muted {
                    h = 2.6
                } else if animating {
                    let s = abs(sin(phase * (1 + 0.17 * Double(i)) + Double(i) * 1.1))
                    h = (3 + CGFloat(s) * 12) * scale
                } else {
                    h = rest[i] * scale
                }
                let bar = NSRect(x: x, y: (rect.height - h) / 2, width: barW, height: h)
                NSBezierPath(roundedRect: bar, xRadius: barW / 2, yRadius: barW / 2).fill()
                x += barW + gap
            }

            if muted {
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 2.5, y: 15.5))
                slash.line(to: NSPoint(x: 17.5, y: 2.5))
                slash.lineCapStyle = .round
                // Cut a gap around the slash first so it reads on top of the bars.
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                slash.lineWidth = 4.2
                slash.stroke()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                slash.lineWidth = 1.8
                NSColor.black.setStroke()
                slash.stroke()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

import Foundation

/// One hook an agent exposes, and the play-sound event it maps to.
struct HookSpec {
    let hook: String
    let event: String
}

/// Where an agent keeps its hooks and which of ours it can run.
struct AgentSpec: Identifiable {
    let id: String
    let name: String
    let configDir: URL
    let file: URL
    let hooks: [HookSpec]

    var installed: Bool {
        FileManager.default.fileExists(atPath: configDir.path) || FileManager.default.fileExists(atPath: file.path)
    }

    static var all: [AgentSpec] {
        let home = Paths.userHome
        return [
            AgentSpec(id: "claude", name: "Claude Code",
                      configDir: home.appendingPathComponent(".claude"),
                      file: home.appendingPathComponent(".claude/settings.json"),
                      hooks: [HookSpec(hook: "SessionStart", event: "session_start"),
                              HookSpec(hook: "UserPromptSubmit", event: "user_prompt_submit"),
                              HookSpec(hook: "Stop", event: "stop"),
                              HookSpec(hook: "Notification", event: "notification")]),
            AgentSpec(id: "codex", name: "Codex",
                      configDir: home.appendingPathComponent(".codex"),
                      file: home.appendingPathComponent(".codex/hooks.json"),
                      hooks: [HookSpec(hook: "SessionStart", event: "session_start"),
                              HookSpec(hook: "UserPromptSubmit", event: "user_prompt_submit"),
                              HookSpec(hook: "Stop", event: "stop")]),
        ]
    }

    static func named(_ id: String) -> AgentSpec? { all.first { $0.id == id } }
}

/// What we remember about a connection so a disconnect can undo it exactly.
struct ConnectionRecord: Codable {
    var replaced: [String: String] = [:]   // hook name -> original command we replaced
    var backup: String?
    var date: String?
}

enum ConnectionRecords {
    static func load() -> [String: ConnectionRecord] {
        guard let data = try? Data(contentsOf: Paths.connections),
              let r = try? JSONDecoder().decode([String: ConnectionRecord].self, from: data) else { return [:] }
        return r
    }

    static func save(_ records: [String: ConnectionRecord]) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(records) else { return }
        try? FileManager.default.createDirectory(at: Paths.home, withIntermediateDirectories: true)
        try? data.write(to: Paths.connections, options: .atomic)
    }
}

struct HookChange {
    enum Kind: String { case add, update, replaceLegacy, restore, remove }
    let kind: Kind
    let hook: String
    let from: String?
    let to: String?
}

struct ChangePlan {
    let spec: AgentSpec
    let oldText: String?
    let newText: String?          // nil means "delete the file"
    let changes: [HookChange]
    let warnings: [String]
    let record: ConnectionRecord
    let disconnect: Bool

    var isNoOp: Bool { oldText == newText }
}

enum HookConnector {
    enum CommandKind { case ours, legacy, otherSound, other }

    // MARK: Commands

    static func command(for h: HookSpec, agent: String) -> String {
        let path = Paths.cli.path
        let quoted = path.contains(" ") ? "'\(path)'" : path
        let base = "AGENT_SOUNDS_AGENT=\(agent) \(quoted) \(h.event)"
        return h.event == "session_start" ? "[ -t 0 ] && \(base) || true" : base
    }

    static func playSoundEvent(in cmd: String) -> String? {
        guard let r = cmd.range(of: #"play-sound'?\s+([a-z_]+)"#, options: .regularExpression) else { return nil }
        return cmd[r].split(whereSeparator: { $0 == " " || $0 == "\t" }).last.map(String.init)
    }

    static func classify(_ cmd: String, for h: HookSpec) -> CommandKind {
        if let ev = playSoundEvent(in: cmd) { return ev == h.event ? .ours : .other }
        let legacy: Bool
        switch h.event {
        case "session_start": legacy = cmd.contains("afplay") && cmd.contains("PeonReady1.wav")
        case "user_prompt_submit": legacy = cmd.contains("afplay") && cmd.contains("PeonYes3.wav")
        case "notification": legacy = cmd.contains("afplay") && cmd.contains("PeonWhat3.wav")
        case "stop": legacy = cmd.contains("stop-sound.sh")
        default: legacy = false
        }
        if legacy { return .legacy }
        return cmd.contains("afplay") ? .otherSound : .other
    }

    // MARK: Rendering

    private static func group(_ command: String) -> JNode {
        .object([("hooks", .array([.object([("type", .string("command")), ("command", .string(command))])]))])
    }

    private static func hooksNode(_ spec: AgentSpec) -> JNode {
        .object(spec.hooks.map { ($0.hook, .array([group(command(for: $0, agent: spec.id))])) })
    }

    // MARK: Connect

    static func planConnect(_ spec: AgentSpec) throws -> ChangePlan {
        let old = try? String(contentsOf: spec.file, encoding: .utf8)
        var rec = ConnectionRecords.load()[spec.id] ?? ConnectionRecord()
        var changes: [HookChange] = []
        var warnings: [String] = []

        if old == nil || old!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let text = JNode.object([("hooks", hooksNode(spec))]).render(indent: "", unit: "  ") + "\n"
            changes = spec.hooks.map { HookChange(kind: .add, hook: $0.hook, from: nil, to: command(for: $0, agent: spec.id)) }
            return ChangePlan(spec: spec, oldText: old, newText: text, changes: changes,
                              warnings: warnings, record: rec, disconnect: false)
        }

        guard let root = try? JSONSerialization.jsonObject(with: Data(old!.utf8)), root is [String: Any] else {
            throw JSONEditError.invalid("\(spec.file.lastPathComponent) is not a JSON object; left untouched")
        }
        var text = JSONText(old!)
        let unit = text.detectUnit()

        var steps = 0
        while try connectStep(spec, &text, unit, &changes, &warnings, &rec) {
            steps += 1
            if steps > 40 { throw JSONEditError.unsupported("too many edits; left untouched") }
        }

        let new = text.string
        try validate(old: old!, new: new, replaced: changes.compactMap(\.from))
        return ChangePlan(spec: spec, oldText: old, newText: new, changes: changes,
                          warnings: warnings, record: rec, disconnect: false)
    }

    /// Makes at most one edit, then returns true so the caller re-scans the new text.
    private static func connectStep(_ spec: AgentSpec, _ text: inout JSONText, _ unit: String,
                                    _ changes: inout [HookChange], _ warnings: inout [String],
                                    _ rec: inout ConnectionRecord) throws -> Bool {
        let rootOpen = text.skipWS(0)
        guard text.char(at: rootOpen) == "{" else { throw JSONEditError.unsupported("top level must be an object") }
        let top = try text.container(at: rootOpen)

        guard let hooksMember = top.children.first(where: { $0.key == "hooks" }) else {
            let base = text.lineIndent(at: rootOpen)
            let node = hooksNode(spec).render(indent: base + unit, unit: unit)
            try text.insertFirst(containerAt: rootOpen, rendered: "\"hooks\": " + node, unit: unit)
            changes += spec.hooks.map { HookChange(kind: .add, hook: $0.hook, from: nil, to: command(for: $0, agent: spec.id)) }
            return true
        }
        guard text.char(at: hooksMember.valueStart) == "{" else {
            throw JSONEditError.unsupported("\"hooks\" is not an object")
        }
        let hooksOpen = hooksMember.valueStart
        let hooksObj = try text.container(at: hooksOpen)

        for h in spec.hooks {
            let desired = command(for: h, agent: spec.id)
            guard let ev = hooksObj.children.first(where: { $0.key == h.hook }) else {
                let base = text.lineIndent(at: hooksOpen)
                let node = JNode.array([group(desired)]).render(indent: base + unit, unit: unit)
                try text.insertFirst(containerAt: hooksOpen, rendered: JSONText.quote(h.hook) + ": " + node, unit: unit)
                changes.append(HookChange(kind: .add, hook: h.hook, from: nil, to: desired))
                return true
            }
            guard text.char(at: ev.valueStart) == "[" else {
                throw JSONEditError.unsupported("hooks.\(h.hook) is not an array")
            }
            var found = false
            for g in try text.container(at: ev.valueStart).children where text.char(at: g.valueStart) == "{" {
                let gm = try text.container(at: g.valueStart)
                guard let hk = gm.children.first(where: { $0.key == "hooks" }),
                      text.char(at: hk.valueStart) == "[" else { continue }
                for he in try text.container(at: hk.valueStart).children where text.char(at: he.valueStart) == "{" {
                    let hm = try text.container(at: he.valueStart)
                    guard let cm = hm.children.first(where: { $0.key == "command" }),
                          text.char(at: cm.valueStart) == "\"" else { continue }
                    let cmd = try text.decodeString(cm.valueStart, cm.end)
                    switch classify(cmd, for: h) {
                    case .ours:
                        found = true
                        if cmd != desired {
                            text.replace(cm.valueStart..<cm.end, with: JSONText.quote(desired))
                            changes.append(HookChange(kind: .update, hook: h.hook, from: cmd, to: desired))
                            return true
                        }
                    case .legacy:
                        found = true
                        text.replace(cm.valueStart..<cm.end, with: JSONText.quote(desired))
                        if rec.replaced[h.hook] == nil { rec.replaced[h.hook] = cmd }
                        changes.append(HookChange(kind: .replaceLegacy, hook: h.hook, from: cmd, to: desired))
                        return true
                    case .otherSound:
                        let w = "\(spec.name) \(h.hook) already runs its own sound command; it was left alone, so you may hear both."
                        if !warnings.contains(w) { warnings.append(w) }
                    case .other:
                        break
                    }
                }
            }
            if !found {
                let base = text.lineIndent(at: ev.valueStart)
                let node = group(desired).render(indent: base + unit, unit: unit)
                try text.insertFirst(containerAt: ev.valueStart, rendered: node, unit: unit)
                changes.append(HookChange(kind: .add, hook: h.hook, from: nil, to: desired))
                return true
            }
        }
        return false
    }

    // MARK: Disconnect

    static func planDisconnect(_ spec: AgentSpec) throws -> ChangePlan {
        var rec = ConnectionRecords.load()[spec.id] ?? ConnectionRecord()
        guard let old = try? String(contentsOf: spec.file, encoding: .utf8) else {
            return ChangePlan(spec: spec, oldText: nil, newText: nil, changes: [], warnings: [],
                              record: rec, disconnect: true)
        }
        guard let root = try? JSONSerialization.jsonObject(with: Data(old.utf8)), root is [String: Any] else {
            throw JSONEditError.invalid("\(spec.file.lastPathComponent) is not a JSON object; left untouched")
        }
        var text = JSONText(old)
        var changes: [HookChange] = []
        var steps = 0
        while try disconnectStep(spec, &text, &changes, &rec) {
            steps += 1
            if steps > 40 { throw JSONEditError.unsupported("too many edits; left untouched") }
        }
        let new = text.string
        try validate(old: old, new: new, replaced: changes.compactMap(\.from), removed: true)
        return ChangePlan(spec: spec, oldText: old, newText: new, changes: changes,
                          warnings: [], record: rec, disconnect: true)
    }

    private static func disconnectStep(_ spec: AgentSpec, _ text: inout JSONText,
                                       _ changes: inout [HookChange], _ rec: inout ConnectionRecord) throws -> Bool {
        let rootOpen = text.skipWS(0)
        guard text.char(at: rootOpen) == "{" else { return false }
        let top = try text.container(at: rootOpen)
        guard let hooksIdx = top.children.firstIndex(where: { $0.key == "hooks" }),
              text.char(at: top.children[hooksIdx].valueStart) == "{" else { return false }
        let hooksOpen = top.children[hooksIdx].valueStart
        let hooksObj = try text.container(at: hooksOpen)

        for (evIdx, ev) in hooksObj.children.enumerated() {
            guard let h = spec.hooks.first(where: { $0.hook == ev.key }),
                  text.char(at: ev.valueStart) == "[" else { continue }
            let groups = try text.container(at: ev.valueStart)

            if groups.children.isEmpty, !changes.isEmpty {
                // We emptied this event earlier in the pass: drop the dangling key.
                try text.removeChild(containerAt: hooksOpen, index: evIdx)
                return true
            }
            for (gIdx, g) in groups.children.enumerated() where text.char(at: g.valueStart) == "{" {
                let gm = try text.container(at: g.valueStart)
                guard let hk = gm.children.first(where: { $0.key == "hooks" }),
                      text.char(at: hk.valueStart) == "[" else { continue }
                let hookList = try text.container(at: hk.valueStart)
                for (hIdx, he) in hookList.children.enumerated() where text.char(at: he.valueStart) == "{" {
                    let hm = try text.container(at: he.valueStart)
                    guard let cm = hm.children.first(where: { $0.key == "command" }),
                          text.char(at: cm.valueStart) == "\"" else { continue }
                    let cmd = try text.decodeString(cm.valueStart, cm.end)
                    guard classify(cmd, for: h) == .ours else { continue }

                    if let original = rec.replaced[h.hook] {
                        text.replace(cm.valueStart..<cm.end, with: JSONText.quote(original))
                        rec.replaced[h.hook] = nil
                        changes.append(HookChange(kind: .restore, hook: h.hook, from: cmd, to: original))
                    } else if hookList.children.count == 1 {
                        try text.removeChild(containerAt: ev.valueStart, index: gIdx)
                        changes.append(HookChange(kind: .remove, hook: h.hook, from: cmd, to: nil))
                    } else {
                        try text.removeChild(containerAt: hk.valueStart, index: hIdx)
                        changes.append(HookChange(kind: .remove, hook: h.hook, from: cmd, to: nil))
                    }
                    return true
                }
            }
        }
        if hooksObj.children.isEmpty, !changes.isEmpty {
            try text.removeChild(containerAt: rootOpen, index: hooksIdx)
            return true
        }
        return false
    }

    // MARK: Apply

    @discardableResult
    static func apply(_ plan: ChangePlan) throws -> URL? {
        guard !plan.isNoOp else { return nil }
        let fm = FileManager.default
        let file = plan.spec.file
        var backup: URL?
        var perms: NSNumber?

        if fm.fileExists(atPath: file.path) {
            perms = (try? fm.attributesOfItem(atPath: file.path))?[.posixPermissions] as? NSNumber
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            let stem = file.lastPathComponent + ".bak-agent-sounds-" + f.string(from: Date())
            var candidate = file.deletingLastPathComponent().appendingPathComponent(stem)
            var n = 2
            while fm.fileExists(atPath: candidate.path) {
                candidate = file.deletingLastPathComponent().appendingPathComponent("\(stem)-\(n)")
                n += 1
            }
            backup = candidate
            try fm.copyItem(at: file, to: candidate)
        }

        if let new = plan.newText {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(new.utf8).write(to: file, options: .atomic)
            if let perms { try? fm.setAttributes([.posixPermissions: perms], ofItemAtPath: file.path) }
        } else {
            try? fm.removeItem(at: file)
        }

        var records = ConnectionRecords.load()
        if plan.disconnect {
            records[plan.spec.id] = nil
        } else {
            var r = plan.record
            r.backup = backup?.path ?? r.backup
            r.date = ISO8601DateFormatter().string(from: Date())
            records[plan.spec.id] = r
        }
        ConnectionRecords.save(records)
        return backup
    }

    // MARK: Safety checks

    /// The edited text must parse, and every command that was not deliberately replaced
    /// or removed must still be there.
    private static func validate(old: String, new: String, replaced: [String], removed: Bool = false) throws {
        guard let newObj = try? JSONSerialization.jsonObject(with: Data(new.utf8)) else {
            throw JSONEditError.invalid("edit produced invalid JSON; file left untouched")
        }
        let oldObj = try JSONSerialization.jsonObject(with: Data(old.utf8))
        let before = Set(commands(in: oldObj)), after = Set(commands(in: newObj))
        let missing = before.subtracting(replaced).subtracting(removed ? before.filter { $0.contains("play-sound") } : [])
            .subtracting(after)
        guard missing.isEmpty else {
            throw JSONEditError.unsupported("edit would have dropped existing hooks; file left untouched")
        }
    }

    private static func commands(in node: Any) -> [String] {
        if let d = node as? [String: Any] {
            return d.flatMap { k, v -> [String] in
                if k == "command", let s = v as? String { return [s] }
                return commands(in: v)
            }
        }
        if let a = node as? [Any] { return a.flatMap(commands(in:)) }
        return []
    }

    // MARK: Diff

    /// Compact line diff for showing what Connect will change.
    static func diff(old: String?, new: String?) -> String {
        let a = (old ?? "").components(separatedBy: "\n"), b = (new ?? "").components(separatedBy: "\n")
        var pre = 0
        while pre < a.count, pre < b.count, a[pre] == b[pre] { pre += 1 }
        var suf = 0
        while suf < a.count - pre, suf < b.count - pre, a[a.count - 1 - suf] == b[b.count - 1 - suf] { suf += 1 }
        let x = Array(a[pre..<(a.count - suf)]), y = Array(b[pre..<(b.count - suf)])
        var lcs = Array(repeating: Array(repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in stride(from: x.count - 1, through: 0, by: -1) {
            for j in stride(from: y.count - 1, through: 0, by: -1) {
                lcs[i][j] = x[i] == y[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var out: [String] = []
        var i = 0, j = 0
        while i < x.count || j < y.count {
            if i < x.count, j < y.count, x[i] == y[j] { i += 1; j += 1 }
            else if j < y.count, i == x.count || lcs[i][j + 1] >= lcs[i + 1][j] {
                out.append("+ \(pre + j + 1): \(y[j])"); j += 1
            } else { out.append("- \(pre + i + 1): \(x[i])"); i += 1 }
        }
        return out.joined(separator: "\n")
    }
}

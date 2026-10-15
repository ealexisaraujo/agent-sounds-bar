import Foundation

enum WireStatus {
    case controlled   // calls play-sound
    case legacy       // plays a sound directly, volume is not controlled
    case absent       // no sound hook on this event

    var label: String {
        switch self {
        case .controlled: return "Controlled by this app"
        case .legacy: return "Plays its own sound: not controlled"
        case .absent: return "No sound hook yet"
        }
    }
}

struct HookWiring: Identifiable {
    let hook: String
    let status: WireStatus
    let command: String?
    var id: String { hook }
}

enum AgentState {
    case notInstalled   // agent's config folder is not there
    case notConnected   // nothing of ours in its hooks yet
    case connected      // every hook we manage calls play-sound
    case drifted        // partly connected, or was connected and got reset
}

struct AgentWiring: Identifiable {
    let spec: AgentSpec
    let fileFound: Bool
    let readable: Bool
    let hooks: [HookWiring]
    let state: AgentState
    var id: String { spec.id }

    var needsRewire: Bool { state == .drifted || hooks.contains { $0.status == .legacy } }
}

/// Reads each agent's hook file (read-only) and reports how it is wired.
enum WiringScanner {
    static func scan() -> [AgentWiring] {
        AgentSpec.all.map(scan)
    }

    static func scan(_ spec: AgentSpec) -> AgentWiring {
        let hadRecord = ConnectionRecords.load()[spec.id] != nil
        guard spec.installed else {
            return AgentWiring(spec: spec, fileFound: false, readable: false, hooks: [], state: .notInstalled)
        }
        guard let data = try? Data(contentsOf: spec.file) else {
            return AgentWiring(spec: spec, fileFound: false, readable: true,
                               hooks: spec.hooks.map { HookWiring(hook: $0.hook, status: .absent, command: nil) },
                               state: hadRecord ? .drifted : .notConnected)
        }
        guard let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return AgentWiring(spec: spec, fileFound: true, readable: false, hooks: [], state: .notConnected)
        }
        let hooks = top["hooks"] as? [String: Any] ?? [:]
        let rows = spec.hooks.map { h -> HookWiring in
            let groups = hooks[h.hook] as? [[String: Any]] ?? []
            let commands = groups.flatMap { g in
                (g["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
            }
            if let c = commands.first(where: { HookConnector.classify($0, for: h) == .ours }) {
                return HookWiring(hook: h.hook, status: .controlled, command: c)
            }
            if let c = commands.first(where: {
                let k = HookConnector.classify($0, for: h)
                return k == .legacy || k == .otherSound
            }) {
                return HookWiring(hook: h.hook, status: .legacy, command: c)
            }
            return HookWiring(hook: h.hook, status: .absent, command: nil)
        }
        let controlled = rows.filter { $0.status == .controlled }.count
        let state: AgentState
        if controlled == rows.count { state = .connected }
        else if controlled > 0 || hadRecord { state = .drifted }
        else { state = .notConnected }
        return AgentWiring(spec: spec, fileFound: true, readable: true, hooks: rows, state: state)
    }
}

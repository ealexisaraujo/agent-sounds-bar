import XCTest
@testable import AgentSoundsBar

final class HookConnectorTests: XCTestCase {
    var tmp: URL!
    var claude: AgentSpec { AgentSpec.named("claude")! }

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("agent-sounds-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("home/.claude"), withIntermediateDirectories: true)
        setenv("AGENT_SOUNDS_USER_HOME", tmp.appendingPathComponent("home").path, 1)
        setenv("AGENT_SOUNDS_HOME", tmp.appendingPathComponent("cfg").path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("AGENT_SOUNDS_USER_HOME")
        unsetenv("AGENT_SOUNDS_HOME")
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: helpers

    func write(_ s: String) throws { try s.write(to: claude.file, atomically: true, encoding: .utf8) }
    func read() throws -> String { try String(contentsOf: claude.file, encoding: .utf8) }

    func connect() throws -> ChangePlan {
        let plan = try HookConnector.planConnect(claude)
        try HookConnector.apply(plan)
        return plan
    }

    func disconnect() throws {
        try HookConnector.apply(try HookConnector.planDisconnect(claude))
    }

    func commands(_ text: String, event: String) throws -> [String] {
        let root = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        let groups = (root["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    func assertAllConnected(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws {
        for h in claude.hooks {
            let c = try commands(text, event: h.hook)
            XCTAssertTrue(c.contains(HookConnector.command(for: h, agent: "claude")), "\(h.hook) not connected", file: file, line: line)
        }
    }

    // MARK: tests

    func testCreatesFileWhenMissing() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: claude.file.path))
        _ = try connect()
        try assertAllConnected(try read())
        XCTAssertEqual(WiringScanner.scan(claude).state, .connected)
    }

    func testEmptyObjectAndCompactJSON() throws {
        for original in ["{}", "{\"hooks\":{}}", "{\"a\":1,\"hooks\":{\"Stop\":[]}}"] {
            try write(original)
            _ = try connect()
            try assertAllConnected(try read())
            try? FileManager.default.removeItem(at: Paths.connections)
        }
    }

    func testAddsHooksSectionAndKeepsEverythingElseByteForByte() throws {
        let original = "{\n  \"model\": \"opus\",\n  \"theme\": \"dark\"\n}\n"
        try write(original)
        _ = try connect()
        let after = try read()
        try assertAllConnected(after)
        XCTAssertTrue(after.contains("\"model\": \"opus\",\n  \"theme\": \"dark\"\n}"))
        try disconnect()
        XCTAssertEqual(try read().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\n", with: ""),
                       "{\"model\":\"opus\",\"theme\":\"dark\"}")
    }

    func testKeepsOtherHooksAndRoundTripsByteIdentical() throws {
        let original = """
        {
          "model": "opus",
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  { "type": "command", "command": "rtk-rewrite.sh" }
                ]
              }
            ],
            "Stop": [
              {
                "hooks": [
                  { "type": "command", "command": "echo done" }
                ]
              }
            ]
          }
        }

        """
        try write(original)
        let plan = try connect()
        let after = try read()
        try assertAllConnected(after)
        XCTAssertTrue(try commands(after, event: "PreToolUse").contains("rtk-rewrite.sh"))
        XCTAssertTrue(try commands(after, event: "Stop").contains("echo done"))
        XCTAssertEqual(plan.changes.filter { $0.kind == .add }.count, 4)

        try disconnect()
        XCTAssertEqual(try read(), original)
    }

    func testReplacesLegacyAndRestoresOriginalOnDisconnect() throws {
        let original = """
        {
          "hooks": {
            "Notification": [
              { "hooks": [ { "type": "command", "command": "afplay /x/.claude/hooks/PeonWhat3.wav" } ] }
            ],
            "SessionStart": [
              { "hooks": [ { "type": "command", "command": "[ -t 0 ] && afplay /x/.claude/hooks/PeonReady1.wav || true" } ] }
            ],
            "Stop": [
              { "hooks": [ { "type": "command", "command": "/x/.claude/hooks/stop-sound.sh" } ] }
            ],
            "UserPromptSubmit": [
              { "hooks": [ { "type": "command", "command": "afplay /x/.claude/hooks/PeonYes3.wav" } ] }
            ]
          }
        }

        """
        try write(original)
        let plan = try connect()
        XCTAssertEqual(plan.changes.filter { $0.kind == .replaceLegacy }.count, 4)
        let after = try read()
        try assertAllConnected(after)
        XCTAssertFalse(after.contains("afplay"))
        XCTAssertFalse(after.contains("stop-sound.sh"))

        try disconnect()
        XCTAssertEqual(try read(), original)
    }

    func testIdempotent() throws {
        try write("{\n  \"x\": 1\n}\n")
        _ = try connect()
        let once = try read()
        let again = try HookConnector.planConnect(claude)
        XCTAssertTrue(again.isNoOp)
        XCTAssertTrue(again.changes.isEmpty)
        XCTAssertEqual(try read(), once)
    }

    func testUpdatesOlderPlaySoundCommandWithoutAgentTag() throws {
        let old = "\(Paths.cli.path) stop"
        try write("{\n  \"hooks\": {\n    \"Stop\": [\n      { \"hooks\": [ { \"type\": \"command\", \"command\": \"\(old)\" } ] }\n    ]\n  }\n}\n")
        let plan = try connect()
        XCTAssertTrue(plan.changes.contains { $0.kind == .update && $0.hook == "Stop" })
        let stop = try commands(try read(), event: "Stop")
        XCTAssertEqual(stop.count, 1)
        XCTAssertTrue(stop[0].hasPrefix("AGENT_SOUNDS_AGENT=claude "))
    }

    func testInvalidJSONIsRefusedAndUntouched() throws {
        let bad = "{ \"hooks\": { oops }"
        try write(bad)
        XCTAssertThrowsError(try HookConnector.planConnect(claude))
        XCTAssertEqual(try read(), bad)
    }

    func testOtherSoundHookIsKeptAndWarned() throws {
        try write("{\n  \"hooks\": {\n    \"Stop\": [\n      { \"hooks\": [ { \"type\": \"command\", \"command\": \"afplay /my/own.wav\" } ] }\n    ]\n  }\n}\n")
        let plan = try connect()
        XCTAssertFalse(plan.warnings.isEmpty)
        let stop = try commands(try read(), event: "Stop")
        XCTAssertTrue(stop.contains("afplay /my/own.wav"))
        XCTAssertEqual(stop.count, 2)
    }

    func testFourSpaceIndentIsMatchedAndFilePermissionsKept() throws {
        try write("{\n    \"a\": 1\n}\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: claude.file.path)
        _ = try connect()
        let after = try read()
        XCTAssertTrue(after.contains("\n    \"hooks\": {\n        \"SessionStart\""), after)
        let perms = try FileManager.default.attributesOfItem(atPath: claude.file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o600)
    }

    func testBackupIsCreatedBesideTheFile() throws {
        try write("{}")
        _ = try connect()
        let siblings = try FileManager.default.contentsOfDirectory(atPath: claude.file.deletingLastPathComponent().path)
        XCTAssertTrue(siblings.contains { $0.hasPrefix("settings.json.bak-agent-sounds-") })
    }

    func testDriftIsDetectedWhenHooksAreWiped() throws {
        try write("{}")
        _ = try connect()
        XCTAssertEqual(WiringScanner.scan(claude).state, .connected)
        try write("{\n  \"hooks\": {}\n}\n")
        XCTAssertEqual(WiringScanner.scan(claude).state, .drifted)
    }

    func testNotInstalledAgent() throws {
        try FileManager.default.removeItem(at: claude.configDir)
        XCTAssertEqual(WiringScanner.scan(claude).state, .notInstalled)
    }

    func testDisconnectOnUntouchedFileIsNoOp() throws {
        let original = "{\n  \"hooks\": {\n    \"Stop\": []\n  }\n}\n"
        try write(original)
        let plan = try HookConnector.planDisconnect(claude)
        XCTAssertTrue(plan.isNoOp)
    }
}

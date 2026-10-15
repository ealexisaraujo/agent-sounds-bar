import XCTest
@testable import AgentSoundsBar

final class SetupInstallerTests: XCTestCase {
    var tmp: URL!
    var resources: URL!

    override func setUpWithError() throws {
        let fm = FileManager.default
        tmp = fm.temporaryDirectory.appendingPathComponent("agent-sounds-setup-\(UUID().uuidString)")
        resources = tmp.appendingPathComponent("res")
        try fm.createDirectory(at: resources.appendingPathComponent("sounds"), withIntermediateDirectories: true)
        try "#!/bin/bash\n# agent-sounds-cli-version: 2\nexit 0\n"
            .write(to: resources.appendingPathComponent("play-sound"), atomically: true, encoding: .utf8)
        for n in ["a.wav", "b.wav"] { fm.createFile(atPath: resources.appendingPathComponent("sounds/\(n)").path, contents: Data([0])) }
        fm.createFile(atPath: resources.appendingPathComponent("sounds/notes.txt").path, contents: Data([0]))
        setenv("AGENT_SOUNDS_HOME", tmp.appendingPathComponent("cfg").path, 1)
        setenv("AGENT_SOUNDS_USER_HOME", tmp.appendingPathComponent("home").path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("AGENT_SOUNDS_HOME")
        unsetenv("AGENT_SOUNDS_USER_HOME")
        try? FileManager.default.removeItem(at: tmp)
    }

    func testFreshMachineIsNotInstalledThenReady() {
        let installer = SetupInstaller(resources: resources)
        XCTAssertEqual(installer.status(), .notInstalled)
        let results = installer.install()
        XCTAssertTrue(results.prefix(4).allSatisfy(\.ok), "\(results)")
        XCTAssertEqual(installer.status(), .ready)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: Paths.cli.path))
    }

    func testCopiesOnlyAudioFilesAndWritesDefaults() throws {
        _ = SetupInstaller(resources: resources).install()
        let sounds = try FileManager.default.contentsOfDirectory(atPath: Paths.sounds.path).sorted()
        XCTAssertEqual(sounds, ["a.wav", "b.wav"])
        let cfg = try JSONDecoder().decode(SoundConfig.self, from: Data(contentsOf: Paths.config))
        XCTAssertEqual(cfg, SoundConfig.defaults)
    }

    func testReinstallKeepsUserSettingsAndSounds() throws {
        let installer = SetupInstaller(resources: resources)
        _ = installer.install()
        var cfg = SoundConfig.defaults
        cfg.volume = 0.2
        try JSONEncoder().encode(cfg).write(to: Paths.config)
        try "mine".write(to: Paths.sounds.appendingPathComponent("a.wav"), atomically: true, encoding: .utf8)

        let results = installer.install()
        XCTAssertTrue(results.prefix(4).allSatisfy(\.ok))
        XCTAssertEqual(try JSONDecoder().decode(SoundConfig.self, from: Data(contentsOf: Paths.config)).volume, 0.2)
        XCTAssertEqual(try String(contentsOf: Paths.sounds.appendingPathComponent("a.wav"), encoding: .utf8), "mine")
    }

    func testNewerBundledScriptIsPickedUpSilently() throws {
        let installer = SetupInstaller(resources: resources)
        _ = installer.install()
        XCTAssertEqual(installer.status(), .ready)

        try "#!/bin/bash\n# agent-sounds-cli-version: 3\nexit 0\n"
            .write(to: resources.appendingPathComponent("play-sound"), atomically: true, encoding: .utf8)
        XCTAssertEqual(installer.status(), .outdated)
        XCTAssertTrue(installer.updateCLIIfNeeded())
        XCTAssertEqual(installer.status(), .ready)
        XCTAssertEqual(installer.installedVersion, 3)
    }

    func testMissingResourcesReportsAClearFailure() {
        let installer = SetupInstaller(resources: nil)
        let failed = installer.install().filter { !$0.ok }
        XCTAssertTrue(failed.contains { $0.title.contains("play-sound") })
        XCTAssertEqual(installer.status(), .notInstalled)
    }

    func testAddSoundNeverOverwrites() throws {
        try FileManager.default.createDirectory(at: Paths.sounds, withIntermediateDirectories: true)
        let src = tmp.appendingPathComponent("ding.wav")
        try "x".write(to: src, atomically: true, encoding: .utf8)
        XCTAssertEqual(SoundLibrary.add(src), "ding.wav")
        XCTAssertEqual(SoundLibrary.add(src), "ding-2.wav")
        XCTAssertEqual(SoundLibrary.add(src), "ding-3.wav")
    }
}

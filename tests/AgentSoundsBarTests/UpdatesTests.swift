import XCTest
@testable import AgentSoundsBar

final class UpdatesTests: XCTestCase {
    private func v(_ s: String) -> AppVersion { AppVersion(s)! }

    private func release(_ tag: String, prerelease: Bool = false, draft: Bool = false) -> Release {
        Release(tagName: tag, htmlURL: URL(string: "https://example.com/\(tag)")!, draft: draft,
                prerelease: prerelease, body: nil,
                assets: [.init(name: "AgentSoundsBar-\(tag).zip", browserDownloadURL: URL(string: "https://example.com/\(tag).zip")!)])
    }

    func testVersionParsing() {
        XCTAssertEqual(v("v1.2.3").core, [1, 2, 3])
        XCTAssertEqual(v("1.2").core, [1, 2, 0])
        XCTAssertEqual(v("1.0.0-beta.2").prerelease, ["beta", "2"])
        XCTAssertEqual(v("v1.0.0-beta.2").description, "1.0.0-beta.2")
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion("1.2.3.4"))
    }

    func testSemverOrdering() {
        let ordered = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11",
                       "1.0.0-rc.1", "1.0.0", "1.0.1", "1.2.0", "1.10.0", "2.0.0"].map(v)
        for (a, b) in zip(ordered, ordered.dropFirst()) { XCTAssertLessThan(a, b, "\(a) < \(b)") }
        XCTAssertEqual(v("v1.0.0"), v("1.0"))
    }

    func testStableIgnoresPrereleasesAndDrafts() {
        let rs = [release("v1.1.0-beta.1", prerelease: true), release("v1.0.1"), release("v1.2.0", draft: true)]
        XCTAssertEqual(Release.newest(in: rs, channel: .stable, newerThan: v("1.0.0"))?.tagName, "v1.0.1")
    }

    func testBetaOffersNewestIncludingPrereleases() {
        let rs = [release("v1.0.1"), release("v1.1.0-beta.1", prerelease: true), release("v1.1.0-beta.2", prerelease: true)]
        XCTAssertEqual(Release.newest(in: rs, channel: .beta, newerThan: v("1.0.0"))?.tagName, "v1.1.0-beta.2")
    }

    func testBetaMovesToTheFinalRelease() {
        let rs = [release("v1.1.0-beta.2", prerelease: true), release("v1.1.0")]
        XCTAssertEqual(Release.newest(in: rs, channel: .beta, newerThan: v("1.1.0-beta.2"))?.tagName, "v1.1.0")
    }

    func testNothingNewerMeansUpToDate() {
        let rs = [release("v1.0.0"), release("v0.9.0"), release("nightly")]
        XCTAssertNil(Release.newest(in: rs, channel: .beta, newerThan: v("1.0.0")))
    }

    func testDecodesGitHubPayload() throws {
        let json = """
        [{"tag_name":"v1.0.1","html_url":"https://github.com/x/y/releases/tag/v1.0.1","draft":false,
          "prerelease":false,"body":"notes","assets":[{"name":"AgentSoundsBar-1.0.1.zip",
          "browser_download_url":"https://github.com/x/y/releases/download/v1.0.1/AgentSoundsBar-1.0.1.zip","size":1}],
          "name":"1.0.1","id":1}]
        """
        let rs = try JSONDecoder().decode([Release].self, from: Data(json.utf8))
        XCTAssertEqual(rs.first?.version, v("1.0.1"))
        XCTAssertEqual(rs.first?.zip?.name, "AgentSoundsBar-1.0.1.zip")
    }

    func testBuildFolderCopyIsADirectInstall() {
        XCTAssertEqual(InstallSource.detect(bundlePath: "/Users/me/src/agent-sounds-bar/build/AgentSoundsBar.app"), .direct)
    }

    func testSystemSoundsDisplayWithoutPath() {
        XCTAssertEqual(SoundLibrary.display(SoundLibrary.system("Glass")), "Glass")
        XCTAssertEqual(SoundLibrary.display("mine.wav"), "mine")
        XCTAssertTrue(SoundLibrary.isBuiltIn(SoundLibrary.system("Glass")))
        XCTAssertFalse(SoundLibrary.isBuiltIn("mine.wav"))
    }

    func testDefaultSoundsExistOnThisMac() {
        for e in SoundEvent.all {
            XCTAssertTrue(FileManager.default.fileExists(atPath: e.defaultSound), e.defaultSound)
        }
    }
}

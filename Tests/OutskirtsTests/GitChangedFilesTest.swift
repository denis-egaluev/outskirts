import Foundation
import Shared
import SystemPackage
import TestShared
import XCTest

/// `Git.changedFiles(since:in:diffFilter:)` against a real git repository created in a temporary directory.
final class GitChangedFilesTest: XCTestCase {
    private var root: FilePath!

    override func setUpWithError() throws {
        root = try FilePath(makeTemporaryDirectory("outskirts-git-changed-files").path)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(atPath: root.string)
    }

    @discardableResult
    private func git(_ arguments: String...) throws -> String {
        try Git.run(arguments, in: root)
    }

    private func write(_ content: String, to name: String) throws {
        try content.write(toFile: root.appending(name).string, atomically: true, encoding: .utf8)
    }

    private func changes(diffFilter: String? = nil) throws -> [String] {
        try Git.changedFiles(since: "HEAD", in: root, diffFilter: diffFilter).map { "\($0.status) \($0.path)" }.sorted()
    }

    func testListsAddedModifiedModeAndRenamedFilesButNotStatOnlyChanges() throws {
        try git("init", "-q")
        try git("config", "user.name", "Test")
        try git("config", "user.email", "test@example.com")
        try git("config", "commit.gpgsign", "false")
        for name in ["modified", "stat", "mode", "renamed"] {
            try write("\(name)\n", to: name)
        }
        try git("add", "-A")
        try git("commit", "-q", "-m", "first")

        try write("changed\n", to: "modified")
        try write("stat\n", to: "stat")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appending("mode").string)
        try git("mv", "renamed", "new-name")
        try write("added\n", to: "added")
        try git("add", "added")

        XCTAssertEqual(try changes(), ["A added", "A new-name", "D renamed", "M mode", "M modified"])
        XCTAssertEqual(try changes(diffFilter: "ACMR"), ["A added", "A new-name", "M mode", "M modified"])
    }
}

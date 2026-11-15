import Foundation
import Logger
import Shared
import SystemPackage
@testable import XcodeSupport
import XCTest

final class XcodebuildFailuresTest: XCTestCase {
    private struct FailingShell: Shell {
        let error: PeripheryError

        func exec(_: [String]) throws -> String {
            throw error
        }
    }

    private final class ProjectStub: XcodeProjectlike {
        let path = FilePath("/tmp/Sample/Sample.xcodeproj")
        let targets: Set<XcodeTarget> = []
        let type = "project"
        let sourceRoot = FilePath("/tmp/Sample")

        func schemes(additionalArguments _: [String]) throws -> Set<String> {
            []
        }
    }

    private let logger = Logger(quiet: true, verbose: false, colorMode: .never)

    private func configurationError(for error: PeripheryError) -> String? {
        let xcodebuild = Xcodebuild(shell: FailingShell(error: error), logger: logger)
        do {
            try xcodebuild.ensureConfigured()
            return nil
        } catch {
            return (error as? PeripheryError)?.errorDescription ?? "\(error)"
        }
    }

    func testEnsureConfigured_keepsTheXcodebuildOutputOfAnUnrelatedFailure() {
        let license = "You have not agreed to the Xcode license agreements."
        let message = configurationError(
            for: .shellCommandFailed(cmd: ["xcodebuild", "-version"], status: 69, output: license)
        )

        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains(license) == true, message ?? "")
        XCTAssertFalse(message?.contains("xcode-select") == true, message ?? "")
    }

    func testEnsureConfigured_pointsToXcodeSelectWhenOnlyTheCommandLineToolsAreSelected() {
        let output = "xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory "
            + "'/Library/Developer/CommandLineTools' is a command line tools instance"
        let message = configurationError(
            for: .shellCommandFailed(cmd: ["xcodebuild", "-version"], status: 1, output: output)
        )

        XCTAssertEqual(message, PeripheryError.xcodebuildNotConfigured.errorDescription)
    }

    func testEnsureConfigured_pointsToXcodeSelectWhenXcodebuildIsMissing() {
        let message = configurationError(for: .executableNotFound(name: "xcodebuild", searchPath: ["/usr/bin"]))

        XCTAssertEqual(message, PeripheryError.xcodebuildNotConfigured.errorDescription)
    }

    func testRefreshCache_doesNotFailWhenAStaleEntryCannotBeEvicted() throws {
        let cache = FilePath(NSTemporaryDirectory()).appending("outskirts-evict-\(UUID().uuidString)")
        let stale = cache.appending("DerivedData-stale")
        try FileManager.default.createDirectory(atPath: stale.string, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: stale.string)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: cache.string)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cache.string)
            try? FileManager.default.removeItem(atPath: cache.string)
        }

        let xcodebuild = Xcodebuild(shell: ShellMock(output: "Xcode 0.0"), logger: logger, cacheDirectory: cache)
        let project = ProjectStub()

        let evicted = try xcodebuild.refreshCache(project: project, schemes: ["A"], maxAgeDays: 1)

        XCTAssertEqual(evicted, [])
        XCTAssertTrue(stale.exists)
    }
}

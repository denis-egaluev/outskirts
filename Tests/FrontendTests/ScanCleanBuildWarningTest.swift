import Configuration
@testable import Frontend
import SystemPackage
import XCTest

/// `--clean-build` cleans the build outskirts runs, so it has no effect when the build is skipped.
final class ScanCleanBuildWarningTest: XCTestCase {
    private func configuration(cleanBuild: Bool, skipBuild: Bool, indexStorePath: [FilePath] = [], derivedDataPath: [FilePath] = []) -> Configuration {
        let configuration = Configuration()
        configuration.apply(\.$cleanBuild, cleanBuild)
        configuration.apply(\.$skipBuild, skipBuild)
        configuration.apply(\.$indexStorePath, indexStorePath)
        configuration.apply(\.$derivedDataPath, derivedDataPath)
        return configuration
    }

    func testCleanBuildWithASkippedBuild_warnsWithTheReason() {
        XCTAssertEqual(
            Scan.ignoredCleanBuildWarning(configuration(cleanBuild: true, skipBuild: true, derivedDataPath: ["DD"])),
            "The '--clean-build' option has no effect as '--derived-data-path' skips the build: rebuild the index store yourself to start from an empty one."
        )
        XCTAssertEqual(
            Scan.ignoredCleanBuildWarning(configuration(cleanBuild: true, skipBuild: true, indexStorePath: ["store"])),
            "The '--clean-build' option has no effect as '--index-store-path' skips the build: rebuild the index store yourself to start from an empty one."
        )
        XCTAssertEqual(
            Scan.ignoredCleanBuildWarning(configuration(cleanBuild: true, skipBuild: true)),
            "The '--clean-build' option has no effect as '--skip-build' is set: rebuild the index store yourself to start from an empty one."
        )
    }

    func testCleanBuildWithABuild_orNoCleanBuild_doesNotWarn() {
        XCTAssertNil(Scan.ignoredCleanBuildWarning(configuration(cleanBuild: true, skipBuild: false)))
        XCTAssertNil(Scan.ignoredCleanBuildWarning(configuration(cleanBuild: false, skipBuild: true, derivedDataPath: ["DD"])))
    }
}

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

    private func everyVariant(_ enabled: Bool, indexStorePath: [FilePath] = [], derivedDataPath: [FilePath] = [], platformConditionalRetention: Bool = false) -> Configuration {
        let configuration = configuration(cleanBuild: false, skipBuild: false, indexStorePath: indexStorePath, derivedDataPath: derivedDataPath)
        configuration.apply(\.$everyVariant, enabled)
        configuration.apply(\.$disablePlatformConditionalRetention, !platformConditionalRetention)
        return configuration
    }

    func testEveryVariant_announcesThePreview() {
        XCTAssertEqual(Scan.everyVariantPreviewNotice(everyVariant(true)), "every_variant is a 4.0 preview: results and options may change")
        XCTAssertNil(Scan.everyVariantPreviewNotice(everyVariant(false)))
    }

    func testEveryVariantWithGivenIndexStores_warnsItIsIgnored() {
        let ignored = "every_variant is ignored: the given index stores are scanned as they are"
        XCTAssertEqual(Scan.everyVariantWarnings(everyVariant(true, indexStorePath: ["store"])), [ignored])
        XCTAssertEqual(Scan.everyVariantWarnings(everyVariant(true, derivedDataPath: ["DD"])), [ignored])
        XCTAssertEqual(Scan.everyVariantWarnings(everyVariant(false, indexStorePath: ["store"])), [])
        XCTAssertEqual(Scan.everyVariantWarnings(everyVariant(true)), [])
    }

    func testEveryVariantWithPlatformConditionalRetention_warnsItIsRedundant() {
        XCTAssertEqual(
            Scan.everyVariantWarnings(everyVariant(true, platformConditionalRetention: true)),
            ["platform conditional retention is redundant with every_variant and will be replaced in 4.0"]
        )
        XCTAssertEqual(Scan.everyVariantWarnings(everyVariant(false, platformConditionalRetention: true)), [])
    }
}

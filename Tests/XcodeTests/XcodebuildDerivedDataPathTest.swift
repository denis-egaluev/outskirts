#if os(macOS)
    import Configuration
    import Foundation
    import Logger
    @testable import ProjectDrivers
    import Shared
    import SystemPackage
    import TestShared
    @testable import XcodeSupport
    import XCTest

    final class XcodebuildDerivedDataPathTest: XCTestCase {
        private final class RecordingShell: Shell, @unchecked Sendable {
            private(set) var commands: [[String]] = []

            func exec(_ args: [String]) throws -> String {
                commands.append(args)
                return args.contains("-showBuildSettings") ? "[]" : "Xcode 0.0"
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

        private func makeXcodebuild(cacheDirectory: FilePath? = TestCacheDirectory.path) -> (Xcodebuild, RecordingShell) {
            let shell = RecordingShell()
            return (Xcodebuild(shell: shell, logger: logger, cacheDirectory: cacheDirectory), shell)
        }

        private func derivedDataPath(
            schemes: [String] = ["SchemeA"],
            buildArguments: [String] = []
        ) throws -> String {
            let (xcodebuild, _) = makeXcodebuild()
            return try xcodebuild.derivedDataPath(for: ProjectStub(), schemes: schemes, buildArguments: buildArguments).string
        }

        func testDerivedDataPathIsIndependentOfSchemeOrder() throws {
            let (xcodebuild, _) = makeXcodebuild()
            let project = ProjectStub()

            let forward = try xcodebuild.derivedDataPath(for: project, schemes: ["SchemeA", "SchemeB", "SchemeC"])
            let reversed = try xcodebuild.derivedDataPath(for: project, schemes: ["SchemeC", "SchemeB", "SchemeA"])
            let shuffled = try xcodebuild.derivedDataPath(for: project, schemes: ["SchemeB", "SchemeC", "SchemeA"])

            XCTAssertEqual(forward, reversed)
            XCTAssertEqual(forward, shuffled)
        }

        func testDerivedDataPathDiffersWhenSchemesDiffer() throws {
            XCTAssertNotEqual(
                try derivedDataPath(schemes: ["SchemeA"]),
                try derivedDataPath(schemes: ["SchemeA", "SchemeB"])
            )
        }

        func testDerivedDataPathDiffersWhenBuildArgumentsDiffer() throws {
            let none = try derivedDataPath()
            let simulator = try derivedDataPath(buildArguments: ["-destination", "generic/platform=iOS Simulator"])
            let device = try derivedDataPath(buildArguments: ["-destination", "generic/platform=iOS"])
            let release = try derivedDataPath(buildArguments: ["-configuration", "Release"])

            XCTAssertEqual(Set([none, simulator, device, release]).count, 4)
        }

        func testDerivedDataPathDependsOnBuildArgumentOrderAndBoundaries() throws {
            XCTAssertNotEqual(
                try derivedDataPath(buildArguments: ["-a", "-b"]),
                try derivedDataPath(buildArguments: ["-b", "-a"])
            )
            XCTAssertNotEqual(
                try derivedDataPath(buildArguments: ["ab", "c"]),
                try derivedDataPath(buildArguments: ["a", "bc"])
            )
        }

        func testDerivedDataPathDiffersWhenSchemeBoundariesDiffer() throws {
            XCTAssertNotEqual(try derivedDataPath(schemes: ["App", "Tests"]), try derivedDataPath(schemes: ["AppTests"]))
        }

        func testDerivedDataPathUsesWideStableHashes() throws {
            let name = try XCTUnwrap(FilePath(try derivedDataPath()).lastComponent?.string)
            let hashes = name.split(separator: "-").dropFirst()

            XCTAssertEqual(hashes.count, 3)
            XCTAssertTrue(hashes.allSatisfy { $0.count == 16 }, name)
        }

        func testDerivedDataPathKeepsExistingNameForEmptyBuildArguments() throws {
            let (xcodebuild, _) = makeXcodebuild()
            let project = ProjectStub()
            let version = try xcodebuild.version().stableHashHex
            let projectHash = project.path.lexicallyNormalized().string.stableHashHex
            let schemesHash = "SchemeA".stableHashHex

            let path = try derivedDataPath()

            let expected = TestCacheDirectory.path.appending("DerivedData-\(version)-\(projectHash)-\(schemesHash)").string
            XCTAssertEqual(path, expected)
        }

        func testDerivedDataPathDefaultsToTheUserCacheDirectory() throws {
            let (xcodebuild, _) = makeXcodebuild(cacheDirectory: nil)

            let path = try xcodebuild.derivedDataPath(for: ProjectStub(), schemes: ["SchemeA"])

            let cachePath = try Constants.cachePath()
            XCTAssertTrue(cachePath.string.hasSuffix("/Library/Caches/com.github.tiny-earth-moon.outskirts"), cachePath.string)
            XCTAssertEqual(path.removingLastComponent(), cachePath)
        }

        func testDriverBuildsInTheTestCacheDirectory() throws {
            let path = FilePath(try buildDerivedDataPath(configuration: Configuration()))

            XCTAssertEqual(path.removingLastComponent(), TestCacheDirectory.path)
            XCTAssertFalse(path.starts(with: try Constants.cachePath()), "A test build writes in the user cache: \(path)")
        }

        func testDerivedDataPathIsIndependentOfOutputOptions() throws {
            var plain = Configuration()
            plain.buildArguments = ["-destination", "generic/platform=iOS Simulator"]

            var reporting = Configuration()
            reporting.buildArguments = plain.buildArguments
            reporting.outputFormat = .json
            reporting.baseline = FilePath("/tmp/baseline.json")
            reporting.writeBaseline = FilePath("/tmp/new-baseline.json")
            reporting.strict = true
            reporting.relativeResults = true
            reporting.reportExclude = [.pattern("**/Generated/**")]

            let first = try buildDerivedDataPath(configuration: plain)
            let second = try buildDerivedDataPath(configuration: reporting)

            XCTAssertEqual(first, second)
        }

        func testDriverWithoutEveryVariantKeepsTheDerivedDataPathOfASingleBuild() throws {
            var configuration = Configuration()
            configuration.buildArguments = ["-destination", "generic/platform=iOS Simulator"]

            let path = try buildDerivedDataPath(configuration: configuration)

            let (xcodebuild, _) = makeXcodebuild()
            let version = try xcodebuild.version().stableHashHex
            let projectHash = ProjectStub().path.lexicallyNormalized().string.stableHashHex
            let argumentsHash = configuration.buildArguments.joined(separator: "\n").stableHashHex
            let expected = "DerivedData-\(version)-\(projectHash)-\("SchemeA".stableHashHex)-\(argumentsHash)"
            XCTAssertEqual(path, TestCacheDirectory.path.appending(expected).string)
        }

        func testDriverBuildsEachVariantInADerivedDataPathOfItsOwn() throws {
            var single = Configuration()
            single.buildArguments = ["SWIFT_TREAT_WARNINGS_AS_ERRORS=NO"]
            var variants = Configuration()
            variants.buildArguments = single.buildArguments
            variants.everyVariant = true
            variants.variantPlatforms = ["macOS", "iOS", "iOS Simulator"]
            variants.variantConfigurations = ["Debug", "Release"]
            variants.variantConditions = ["FEATURE_X"]

            let singlePaths = try buildDerivedDataPaths(configuration: single)
            let variantPaths = try buildDerivedDataPaths(configuration: variants)

            XCTAssertEqual(singlePaths.count, 1)
            XCTAssertEqual(variantPaths.count, 7)
            XCTAssertEqual(Set(variantPaths).count, 7)
            XCTAssertFalse(variantPaths.contains(singlePaths[0]))
            XCTAssertEqual(try buildDerivedDataPaths(configuration: variants), variantPaths, "the same variants reuse their DerivedData")
        }

        private func buildDerivedDataPaths(configuration: Configuration) throws -> [String] {
            let (xcodebuild, shell) = makeXcodebuild()
            let driver = XcodeProjectDriver(
                logger: logger,
                configuration: configuration,
                xcodebuild: xcodebuild,
                project: ProjectStub(),
                schemes: ["SchemeA"]
            )

            try driver.build()

            return try shell.commands.filter { $0.contains("build-for-testing") }.map { command in
                let index = try XCTUnwrap(command.firstIndex(of: "-derivedDataPath"))
                return command[index + 1]
            }
        }

        private func buildDerivedDataPath(configuration: Configuration) throws -> String {
            let (xcodebuild, shell) = makeXcodebuild()
            let driver = XcodeProjectDriver(
                logger: logger,
                configuration: configuration,
                xcodebuild: xcodebuild,
                project: ProjectStub(),
                schemes: ["SchemeA"]
            )

            try driver.build()

            let command = try XCTUnwrap(shell.commands.last { $0.contains("build-for-testing") })
            let index = try XCTUnwrap(command.firstIndex(of: "-derivedDataPath"))
            return command[index + 1]
        }
    }
#endif

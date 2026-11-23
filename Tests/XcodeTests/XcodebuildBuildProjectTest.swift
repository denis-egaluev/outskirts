import Configuration
import Foundation
import Indexer
import Logger
import Shared
import SystemPackage
import TestShared
@testable import XcodeSupport
import XCTest
#if os(macOS)
    @testable import ProjectDrivers
#endif

final class XcodebuildBuildProjectTest: XCTestCase {
    private var xcodebuild: Xcodebuild!
    private var project: XcodeProject!

    override func setUp() {
        super.setUp()

        let logger = Logger(quiet: true, verbose: false, colorMode: .never)
        let shell = ShellImpl(logger: logger)
        var loadedProjectPaths: Set<FilePath> = []
        xcodebuild = Xcodebuild(shell: shell, logger: logger, cacheDirectory: TestCacheDirectory.path)
        project = try! XcodeProject(path: UIKitProjectPath, loadedProjectPaths: &loadedProjectPaths, xcodebuild: xcodebuild, shell: shell, logger: logger)
    }

    override func tearDown() {
        xcodebuild = nil
        project = nil
        super.tearDown()
    }

    func testBuildSchemeWithWhitespace() throws {
        let scheme = "Scheme With Spaces"
        try xcodebuild.build(project: project, scheme: scheme, allSchemes: [scheme])
    }
}

#if os(macOS)
    /// The builds of the Xcode project driver with and without `every_variant`, through a shell that only records them.
    extension XcodebuildBuildProjectTest {
        private final class ProjectStub: XcodeProjectlike {
            let path = FilePath("/tmp/Sample/Sample.xcodeproj")
            let targets: Set<XcodeTarget> = []
            let type = "project"
            let sourceRoot = FilePath("/tmp/Sample")

            func schemes(additionalArguments _: [String]) throws -> Set<String> {
                []
            }
        }

        private static let variantSchemes: Set<String> = ["SchemeA", "SchemeB"]

        private var quietLogger: Logger {
            Logger(quiet: true, verbose: false, colorMode: .never)
        }

        /// A cache directory of its own, removed at the end of the test.
        private func makeCacheDirectory() throws -> FilePath {
            let path = TestCacheDirectory.path.appending("variants-\(UUID().uuidString)")
            try FileManager.default.createDirectory(atPath: path.string, withIntermediateDirectories: true)
            addTeardownBlock { try FileManager.default.removeItem(atPath: path.string) }
            return path
        }

        private func makeDriver(
            _ configuration: Configuration,
            shell: RecordingShellMock,
            project: XcodeProjectlike = ProjectStub()
        ) throws -> (XcodeProjectDriver, Xcodebuild) {
            let xcodebuild = try Xcodebuild(shell: shell, logger: quietLogger, cacheDirectory: makeCacheDirectory())
            let driver = XcodeProjectDriver(logger: quietLogger, configuration: configuration, xcodebuild: xcodebuild, project: project, schemes: Self.variantSchemes)
            return (driver, xcodebuild)
        }

        private func loadUIKitProject(shell: RecordingShellMock) throws -> XcodeProject {
            var loadedProjectPaths: Set<FilePath> = []
            return try XcodeProject(
                path: UIKitProjectPath,
                loadedProjectPaths: &loadedProjectPaths,
                xcodebuild: Xcodebuild(shell: shell, logger: quietLogger, cacheDirectory: makeCacheDirectory()),
                shell: shell,
                logger: quietLogger
            )
        }

        private func everyVariant(platforms: [String], configurations: [String] = []) -> Configuration {
            var configuration = Configuration()
            configuration.everyVariant = true
            configuration.variantPlatforms = platforms
            configuration.variantConfigurations = configurations
            configuration.buildArguments = ["SWIFT_TREAT_WARNINGS_AS_ERRORS=NO"]
            return configuration
        }

        private func derivedDataPath(_ xcodebuild: Xcodebuild, arguments: [String]) throws -> FilePath {
            try xcodebuild.derivedDataPath(for: ProjectStub(), schemes: Array(Self.variantSchemes), buildArguments: arguments)
        }

        /// The command 3.27 runs to build a scheme with these build arguments.
        private func expectedCommand(scheme: String, xcodebuild: Xcodebuild, arguments: [String]) throws -> [String] {
            try [
                "xcodebuild", "-project", "/tmp/Sample/Sample.xcodeproj", "-scheme", scheme, "-parallelizeTargets",
                "-derivedDataPath", derivedDataPath(xcodebuild, arguments: arguments).string,
                "-quiet", "build-for-testing", "CODE_SIGNING_ALLOWED=NO", "ENABLE_BITCODE=NO", "DEBUG_INFORMATION_FORMAT=dwarf",
                "COMPILER_INDEX_STORE_ENABLE=YES", "INDEX_ENABLE_DATA_STORE=YES",
            ] + arguments
        }

        private func bySchemes(_ commands: some Sequence<[String]>) -> [[String]] {
            commands.sorted { scheme(of: $0) < scheme(of: $1) }
        }

        private func scheme(of command: [String]) -> String {
            command.firstIndex(of: "-scheme").map { command[$0 + 1] } ?? ""
        }

        func testWithoutEveryVariant_buildsEachSchemeOnceWithTheConfiguredArguments() throws {
            var configuration = Configuration()
            configuration.buildArguments = ["-destination", "generic/platform=iOS Simulator"]
            let shell = RecordingShellMock()
            let (driver, xcodebuild) = try makeDriver(configuration, shell: shell)

            try driver.build()

            XCTAssertEqual(bySchemes(shell.buildCommands), try ["SchemeA", "SchemeB"].map {
                try expectedCommand(scheme: $0, xcodebuild: xcodebuild, arguments: configuration.buildArguments)
            })
            XCTAssertEqual(try driver.builds(), [.init(variant: nil, arguments: configuration.buildArguments, schemes: Self.variantSchemes.sorted())])
        }

        func testEveryVariant_buildsEverySchemeForEachVariantWithItsArguments() throws {
            let configuration = everyVariant(platforms: ["macOS", "iOS Simulator"], configurations: ["Debug", "Release"])
            let shell = RecordingShellMock()
            let (driver, xcodebuild) = try makeDriver(configuration, shell: shell)

            try driver.build()

            let base = configuration.buildArguments
            let variantArguments = [
                base + ["-destination", "generic/platform=macOS", "-configuration", "Debug"],
                base + ["-destination", "generic/platform=macOS", "-configuration", "Release", "ENABLE_TESTABILITY=YES"],
                base + ["-destination", "generic/platform=iOS Simulator", "-configuration", "Debug"],
                base + ["-destination", "generic/platform=iOS Simulator", "-configuration", "Release", "ENABLE_TESTABILITY=YES"],
            ]
            XCTAssertEqual(shell.buildCommands.count, 8)
            for (index, arguments) in variantArguments.enumerated() {
                let commands = bySchemes(shell.buildCommands.dropFirst(index * 2).prefix(2))
                XCTAssertEqual(commands, try ["SchemeA", "SchemeB"].map {
                    try expectedCommand(scheme: $0, xcodebuild: xcodebuild, arguments: arguments)
                })
            }
        }

        func testEveryVariant_readsThePlatformsSetByAnXcconfigOncePerSchemeWithTheBuildArguments() throws {
            let configuration = everyVariant(platforms: ["iOS", "macOS"])
            configuration.buildArguments = ["-xcconfig", "Custom.xcconfig"]
            let shell = RecordingShellMock(buildSettings: [
                "SchemeA": #"[{ "target": "A", "buildSettings": { "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator" } }]"#,
                "SchemeB": #"[{ "target": "B", "buildSettings": { "SDKROOT": "macosx" } }]"#,
            ])
            let (driver, _) = try makeDriver(configuration, shell: shell)

            let builds = try driver.builds()

            XCTAssertEqual(builds.map { "\($0.variant.map(\.description) ?? ""): \($0.schemes.joined(separator: ", "))" }, [
                "iOS · Debug: SchemeA",
                "macOS · Debug: SchemeB",
            ])
            XCTAssertEqual(shell.showBuildSettingsCommands.count, 2)
            XCTAssertTrue(shell.showBuildSettingsCommands.allSatisfy { $0.suffix(2) == ["-xcconfig", "Custom.xcconfig"] })
        }

        func testWithoutEveryVariant_noBuildSettingsAreRead() throws {
            let shell = RecordingShellMock()
            let (driver, _) = try makeDriver(Configuration(), shell: shell)

            _ = try driver.builds()

            XCTAssertEqual(shell.showBuildSettingsCommands, [])
        }

        func testEveryVariant_failsNamingTheVariantWhosePlatformIsUnavailable() throws {
            let configuration = everyVariant(platforms: ["macOS", "visionOS Simulator", "iOS"])
            let shell = RecordingShellMock(failing: "generic/platform=visionOS Simulator")
            let (driver, _) = try makeDriver(configuration, shell: shell)

            XCTAssertThrowsError(try driver.build()) { error in
                guard case let .variantBuildFailed(variant, scheme, underlying) = error as? PeripheryError else {
                    return XCTFail("unexpected error \(error)")
                }

                XCTAssertEqual(variant, "visionOS Simulator · Debug")
                XCTAssertTrue(Self.variantSchemes.contains(scheme))
                XCTAssertTrue("\(underlying)".contains("Unable to find a destination"), "\(underlying)")
                XCTAssertTrue("\(error)".contains("'visionOS Simulator · Debug'"), "\(error)")
            }
            XCTAssertEqual(shell.buildCommands.count, 3, "builds macOS, then stops at the first visionOS Simulator scheme")
            XCTAssertFalse(shell.buildCommands.contains { $0.contains("generic/platform=iOS") })
        }

        func testEveryVariant_cleanBuildRemovesTheDerivedDataOfEachVariant() throws {
            var configuration = everyVariant(platforms: ["macOS", "iOS Simulator"])
            configuration.cleanBuild = true
            let shell = RecordingShellMock()
            let (driver, xcodebuild) = try makeDriver(configuration, shell: shell)
            let paths = try driver.builds().map { try derivedDataPath(xcodebuild, arguments: $0.arguments) }
            for path in paths {
                try FileManager.default.createDirectory(atPath: path.appending("Stale").string, withIntermediateDirectories: true)
            }

            try driver.build()

            XCTAssertEqual(Set(paths).count, 2)
            XCTAssertTrue(paths.allSatisfy { !$0.exists })
            XCTAssertEqual(shell.buildCommands.count, 4)
        }

        func testEveryVariant_allConfigurationsAreThoseOfTheProject() throws {
            let shell = RecordingShellMock()
            let project = try loadUIKitProject(shell: shell)
            let (driver, _) = try makeDriver(everyVariant(platforms: ["iOS Simulator"], configurations: ["all"]), shell: shell, project: project)

            let variants = try driver.builds().compactMap(\.variant)

            XCTAssertEqual(variants.map(\.description), ["iOS Simulator · Debug", "iOS Simulator · Release"])
        }

        func testEveryVariant_planReadsTheIndexStoreOfEachVariant() throws {
            let shell = RecordingShellMock()
            let (driver, xcodebuild) = try makeDriver(everyVariant(platforms: ["macOS", "iOS Simulator"]), shell: shell)
            let stores = try driver.builds().map {
                try derivedDataPath(xcodebuild, arguments: $0.arguments).appending("Index.noindex/DataStore")
            }
            for store in stores {
                try FileManager.default.createDirectory(atPath: store.string, withIntermediateDirectories: true)
            }

            XCTAssertEqual(try driver.variantIndexStorePaths(driver.builds()), Set(stores))
            XCTAssertEqual(Set(stores).count, 2)
        }

        func testEveryVariant_skippedBuildWithoutAVariantStoreFailsNamingTheVariant() throws {
            var configuration = everyVariant(platforms: ["macOS"])
            configuration.skipBuild = true
            let shell = RecordingShellMock()
            let (driver, _) = try makeDriver(configuration, shell: shell)

            try driver.build()

            XCTAssertTrue(shell.buildCommands.isEmpty)
            XCTAssertThrowsError(try driver.plan(logger: quietLogger.contextualized(with: "index"))) { error in
                guard case let .variantIndexStoreNotFound(variant, _) = error as? PeripheryError else {
                    return XCTFail("unexpected error \(error)")
                }

                XCTAssertEqual(variant, "macOS · Debug")
            }
        }

        func testEveryVariant_refreshingTheCacheKeepsTheBuildOfEveryVariant() throws {
            let shell = RecordingShellMock()
            let (driver, xcodebuild) = try makeDriver(everyVariant(platforms: ["macOS", "iOS Simulator"]), shell: shell)
            let arguments = try driver.builds().map(\.arguments)
            let variantPaths = try arguments.map { try derivedDataPath(xcodebuild, arguments: $0) }
            let stale = try XCTUnwrap(xcodebuild.cacheDirectory).appending("DerivedData-stale")
            for path in variantPaths + [stale] {
                try FileManager.default.createDirectory(atPath: path.string, withIntermediateDirectories: true)
                try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: path.string)
            }

            let evicted = try xcodebuild.refreshCache(project: ProjectStub(), schemes: Array(Self.variantSchemes), buildArgumentSets: arguments, maxAgeDays: 1)

            XCTAssertEqual(evicted.map(\.name), ["DerivedData-stale"])
            XCTAssertTrue(variantPaths.allSatisfy(\.exists))
        }

        func testEveryVariant_strictCoverageExpectsOnlyThePlatformsTheVariantsBuild() throws {
            let project = try loadUIKitProject(shell: RecordingShellMock())
            let targets = Dictionary(project.targets.map { ($0.name, $0) }) { first, _ in first }

            let all = XcodeProjectDriver.coverageTargets(of: targets)
            let iOSOnly = XcodeProjectDriver.coverageTargets(of: targets, variantPlatforms: { _ in [.iOS] })

            XCTAssertTrue(all.values.contains { $0.platforms.contains(.watchOS) })
            XCTAssertTrue(iOSOnly.values.allSatisfy { $0.platforms.isSubset(of: [.iOS]) })
            XCTAssertTrue(iOSOnly.values.contains { $0.platforms == [.iOS] })
            XCTAssertEqual(iOSOnly.keys.sorted(), all.keys.sorted())
        }
    }
#endif

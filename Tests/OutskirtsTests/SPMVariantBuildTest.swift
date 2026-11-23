import Configuration
import Foundation
import Logger
@testable import ProjectDrivers
import Shared
import SystemPackage
import TestShared
import XCTest

/// The builds of the Swift package driver with and without `every_variant`, through a shell that only records them.
final class SPMVariantBuildTest: XCTestCase {
    /// Records the commands it runs; `swift build --show-bin-path` answers the `swiftbuild` products directory of the
    /// scratch path, and a command containing the argument `failing` fails as `swift build` does.
    private final class RecordingShell: Shell, @unchecked Sendable {
        private(set) var commands: [[String]] = []
        private let failing: String?

        init(failing: String? = nil) {
            self.failing = failing
        }

        var buildCommands: [[String]] {
            commands.filter { $0.starts(with: ["swift", "build", "--build-tests"]) }
        }

        func exec(_ args: [String]) throws -> String {
            commands.append(args)
            if let failing, args.contains(failing) {
                throw PeripheryError.shellCommandFailed(cmd: args, status: 1, output: "error: no available Swift SDK for '\(failing)'")
            }
            if args.contains("--show-bin-path") {
                let scratch = args.firstIndex(of: "--scratch-path").map { args[$0 + 1] } ?? ".build"
                return "\(scratch)/out/Products/Debug\n"
            }
            return ""
        }
    }

    private var root: URL!

    override func setUpWithError() throws {
        root = try makeTemporaryDirectory("outskirts-spm-variants")
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private var scratch: String {
        root.appendingPathComponent("scratch").path
    }

    private func configuration(_ configure: (Configuration) -> Void = { _ in }) -> Configuration {
        let configuration = Configuration()
        configuration.buildArguments = ["--scratch-path", scratch, "-Xswiftc", "-warnings-as-errors"]
        configure(configuration)
        return configuration
    }

    private func everyVariant(_ configure: (Configuration) -> Void = { _ in }) -> Configuration {
        configuration {
            $0.everyVariant = true
            $0.variantConfigurations = ["all"]
            $0.variantConditions = ["FOO"]
            configure($0)
        }
    }

    private func driver(_ configuration: Configuration, shell: RecordingShell) -> SPMProjectDriver {
        let logger = Logger(quiet: true, verbose: false, colorMode: .never)
        return SPMProjectDriver(pkg: SPM.Package(configuration: configuration, shell: shell, logger: logger), configuration: configuration, logger: logger)
    }

    // MARK: - Without every_variant

    func testWithoutEveryVariant_buildsOnceWithTheConfiguredArguments() throws {
        let configuration = configuration { $0.cleanBuild = true }
        let shell = RecordingShell()
        let driver = driver(configuration, shell: shell)

        try driver.build()

        XCTAssertEqual(try driver.builds(), [.init(variant: nil, arguments: configuration.buildArguments, scratchPath: nil)])
        XCTAssertEqual(shell.commands, [
            ["swift", "package", "clean", "--scratch-path", scratch],
            ["swift", "build", "--build-tests"] + configuration.buildArguments,
        ])
    }

    // MARK: - With every_variant

    func testEveryVariant_buildsEachVariantInItsOwnScratchPath() throws {
        let shell = RecordingShell()
        let driver = driver(everyVariant(), shell: shell)

        try driver.build()

        let builds = try driver.builds()
        XCTAssertEqual(builds.compactMap(\.variant?.description), ["host · debug", "host · release", "host · debug · FOO"])
        let variantArguments = [
            ["-c", "debug"],
            ["-c", "release", "-Xswiftc", "-enable-testing"],
            ["-c", "debug", "-Xswiftc", "-DFOO"],
        ]
        XCTAssertEqual(shell.buildCommands.count, 3)
        for (index, arguments) in variantArguments.enumerated() {
            let scratchPath = try XCTUnwrap(builds[index].scratchPath)
            XCTAssertEqual(scratchPath.removingLastComponent(), FilePath(scratch).appending("outskirts-variants"))
            let indexStoreArguments = builds[index].variant?.isDebug == false
                ? ["-Xswiftc", "-index-store-path", "-Xswiftc", scratchPath.appending("index-store").string]
                : []
            XCTAssertEqual(
                shell.buildCommands[index],
                ["swift", "build", "--build-tests", "-Xswiftc", "-warnings-as-errors"] + arguments + ["--scratch-path", scratchPath.string] + indexStoreArguments
            )
        }
        XCTAssertEqual(builds.map(\.indexStorePath), [nil, builds[1].scratchPath?.appending("index-store"), nil])
        XCTAssertEqual(Set(builds.compactMap(\.scratchPath)).count, 3)
    }

    func testEveryVariant_scratchPathsAreStableAcrossScans() throws {
        let first = try driver(everyVariant(), shell: RecordingShell()).builds()
        let second = try driver(everyVariant(), shell: RecordingShell()).builds()

        XCTAssertEqual(first, second)
    }

    func testEveryVariant_withoutAConfiguredScratchPathBuildsUnderTheBuildDirectory() {
        let variant = BuildVariant(platform: .triple("arm64-apple-ios17.0-simulator"), configuration: "debug")

        let build = SPMProjectDriver.variantBuild(variant, buildArguments: ["--build-path=custom", "-v"], packagePath: "/package")
        let defaultBuild = SPMProjectDriver.variantBuild(variant, buildArguments: ["-v"], packagePath: "/package")

        XCTAssertEqual(build.scratchPath?.removingLastComponent(), "/package/custom/outskirts-variants")
        XCTAssertEqual(defaultBuild.scratchPath?.removingLastComponent(), "/package/.build/outskirts-variants")
        XCTAssertEqual(build.scratchPath, defaultBuild.scratchPath.map { FilePath("/package/custom/outskirts-variants").appending($0.lastComponent!.string) })
        XCTAssertEqual(defaultBuild.arguments, ["-v", "--triple", "arm64-apple-ios17.0-simulator", "-c", "debug", "--scratch-path", defaultBuild.scratchPath!.string])
    }

    func testEveryVariant_aForwardedArgumentIsNotAScratchPath() {
        let split = SPMProjectDriver.splitScratchPath(["-Xswiftc", "--scratch-path", "--scratch-path", "a", "--scratch-path=b"])

        XCTAssertEqual(split.scratchPath, "b")
        XCTAssertEqual(split.others, ["-Xswiftc", "--scratch-path"])
    }

    func testEveryVariant_cleanBuildCleansTheScratchPathOfEachVariant() throws {
        let shell = RecordingShell()
        let driver = driver(everyVariant { $0.cleanBuild = true }, shell: shell)

        try driver.build()

        let cleaned = shell.commands.filter { $0.starts(with: ["swift", "package", "clean"]) }
        XCTAssertEqual(cleaned, try driver.builds().map { ["swift", "package", "clean", "--scratch-path", $0.scratchPath!.string] })
    }

    func testEveryVariant_failsNamingTheVariantWhoseTripleIsUnavailable() throws {
        let shell = RecordingShell(failing: "wasm32-unknown-wasi")
        let driver = driver(everyVariant { $0.variantTriples = ["x86_64-unknown-linux-gnu", "wasm32-unknown-wasi"] }, shell: shell)

        XCTAssertThrowsError(try driver.build()) { error in
            guard case let .packageVariantBuildFailed(variant, underlying) = error as? PeripheryError else {
                return XCTFail("Unexpected error: \(error)")
            }

            XCTAssertEqual(variant, "wasm32-unknown-wasi · debug")
            XCTAssertTrue(error.localizedDescription.contains("'wasm32-unknown-wasi · debug'"))
            XCTAssertTrue(error.localizedDescription.contains("variant_triples"))
            guard case .shellCommandFailed = underlying as? PeripheryError else {
                return XCTFail("Unexpected underlying error: \(underlying)")
            }
        }
        XCTAssertEqual(shell.buildCommands.count, 3, "the variants before the failing one are built, the following ones are not")
    }

    func testEveryVariant_planReadsTheIndexStoreOfEachVariant() throws {
        let configuration = everyVariant()
        let shell = RecordingShell()
        let driver = driver(configuration, shell: shell)
        let stores = try driver.builds().map { try $0.indexStorePath ?? XCTUnwrap($0.scratchPath).appending("out") }
        for store in stores {
            try FileManager.default.createDirectory(atPath: store.appending("v5").string, withIntermediateDirectories: true)
        }

        XCTAssertEqual(try driver.variantIndexStorePaths(driver.builds()), Set(stores))
        XCTAssertEqual(stores.count, 3)
    }

    func testEveryVariant_skippedBuildWithoutAVariantStoreFailsNamingTheVariant() throws {
        let shell = RecordingShell()
        let driver = driver(everyVariant { $0.skipBuild = true }, shell: shell)
        let builds = try driver.builds()
        try FileManager.default.createDirectory(atPath: XCTUnwrap(builds[0].scratchPath).appending("out/v5").string, withIntermediateDirectories: true)

        try driver.build()
        XCTAssertTrue(shell.buildCommands.isEmpty)

        XCTAssertThrowsError(try driver.variantIndexStorePaths(builds)) { error in
            guard case let .variantIndexStoreNotFound(variant, path) = error as? PeripheryError else {
                return XCTFail("Unexpected error: \(error)")
            }

            XCTAssertEqual(variant, "host · release")
            XCTAssertEqual(path, builds[1].scratchPath?.string)
        }
    }

    func testEveryVariant_strictCoverageExpectsThePlatformsOfTheVariants() throws {
        let triples = try driver(everyVariant { $0.variantTriples = ["arm64-apple-ios17.0-simulator", "arm64-apple-macosx14.0"] }, shell: RecordingShell()).builds()
        let unknown = try driver(everyVariant { $0.variantTriples = ["arm64-apple-ios17.0", "wasm32-unknown-wasi"] }, shell: RecordingShell()).builds()
        let host = try driver(everyVariant(), shell: RecordingShell()).builds()

        XCTAssertEqual(SPMProjectDriver.variantPlatforms(triples), [.iOS, .macOS])
        XCTAssertEqual(SPMProjectDriver.variantPlatforms(unknown), [])
        XCTAssertEqual(SPMProjectDriver.variantPlatforms(host), [.host])
    }
}

#if os(macOS)
    import Configuration
    import Foundation
    import Indexer
    import Logger
    @testable import ProjectDrivers
    import Shared
    import SystemPackage
    import TestShared
    @testable import XcodeSupport
    import XCTest

    /// A project with one scheme per platform, as XcodeGen generates them: `App-iOS` and `App-macOS` each build their
    /// app, which depends on the multi-platform framework `Core`; `Tools` is built by no scheme.
    final class XcodeSchemeVariantTest: XCTestCase {
        private struct TargetSpec {
            let name: String
            let platforms: String
            /// The indices of the targets it depends on.
            let dependencies: [Int]
        }

        private static let targetSpecs = [
            TargetSpec(name: "App-iOS", platforms: "iphoneos iphonesimulator", dependencies: [2]),
            TargetSpec(name: "App-macOS", platforms: "macosx", dependencies: [2]),
            TargetSpec(name: "Core", platforms: "iphoneos iphonesimulator macosx", dependencies: []),
            TargetSpec(name: "Tools", platforms: "macosx", dependencies: []),
        ]

        private let logger = Logger(quiet: true, verbose: false, colorMode: .never)
        private var root: FilePath!
        private var projectPath: FilePath {
            root.appending("Sample.xcodeproj")
        }

        override func setUpWithError() throws {
            try super.setUpWithError()
            root = FilePath(FileManager.default.temporaryDirectory.path).appending("XcodeSchemeVariantTest-\(UUID().uuidString)")
            try FileManager.default.createDirectory(atPath: projectPath.string, withIntermediateDirectories: true)
            try Self.projectFile().write(toFile: projectPath.appending("project.pbxproj").string, atomically: true, encoding: .utf8)
            try writeScheme(target: "App-iOS", in: "xcshareddata/xcschemes")
            try writeScheme(target: "App-macOS", in: "xcuserdata/dev.xcuserdatad/xcschemes")
        }

        override func tearDownWithError() throws {
            try FileManager.default.removeItem(atPath: root.string)
            root = nil
            try super.tearDownWithError()
        }

        // MARK: - Scheme targets

        func testSchemeTargets_areTheEntriesOfTheSchemeFileAndTheirDependencies() throws {
            let project = try loadProject(shell: RecordingShellMock())
            var warnings: [String] = []

            let iOS = try XCTUnwrap(XcodeSchemeTargets.load(scheme: "App-iOS", in: project) { warnings.append($0) })
            let macOS = try XCTUnwrap(XcodeSchemeTargets.load(scheme: "App-macOS", in: project) { warnings.append($0) })

            XCTAssertEqual(names(iOS.named), ["App-iOS"])
            XCTAssertEqual(names(iOS.built), ["App-iOS", "Core"])
            XCTAssertEqual(names(macOS.named), ["App-macOS"], "read from the user data")
            XCTAssertEqual(names(macOS.built), ["App-macOS", "Core"])
            XCTAssertEqual(warnings, [])
        }

        func testSchemeTargets_ofASchemeWithoutFileAreTheTargetOfItsName() throws {
            let project = try loadProject(shell: RecordingShellMock())

            let core = XcodeSchemeTargets.load(scheme: "Core", in: project) { XCTFail($0) }
            let packages = XcodeSchemeTargets.load(scheme: "Packages", in: project) { XCTFail($0) }

            XCTAssertEqual(core.map { names($0.named) }, ["Core"])
            XCTAssertNil(packages)
        }

        // MARK: - Builds

        func testEveryVariant_buildsEachPerPlatformSchemeOnlyForTheDetectedPlatformOfItsTargets() throws {
            let shell = RecordingShellMock()
            let (driver, xcodebuild, project) = try makeDriver(everyVariant(), shell: shell)

            try driver.build()

            XCTAssertEqual(try builtSchemes(shell, xcodebuild: xcodebuild, project: project), [
                "App-iOS: generic/platform=iOS",
                "App-macOS: generic/platform=macOS",
            ])
        }

        func testEveryVariant_buildsEachSchemeOnlyForTheListedPlatformsItsTargetsSupport() throws {
            let shell = RecordingShellMock()
            let (driver, xcodebuild, project) = try makeDriver(everyVariant(platforms: ["iOS Simulator", "macOS", "Mac Catalyst"]), shell: shell)

            try driver.build()

            XCTAssertEqual(try builtSchemes(shell, xcodebuild: xcodebuild, project: project), [
                "App-iOS: generic/platform=iOS Simulator",
                "App-macOS: generic/platform=macOS",
                "App-iOS: platform=macOS,variant=Mac Catalyst",
            ])
        }

        func testEveryVariant_planReadsTheIndexStoreOfVariantsBuiltBySomeSchemes() throws {
            let shell = RecordingShellMock()
            let (driver, xcodebuild, project) = try makeDriver(everyVariant(), shell: shell)
            let stores = try driver.builds().map {
                try xcodebuild.derivedDataPath(for: project, schemes: Self.schemes, buildArguments: $0.arguments).appending("Index.noindex/DataStore")
            }
            for store in stores {
                try FileManager.default.createDirectory(atPath: store.string, withIntermediateDirectories: true)
            }

            XCTAssertEqual(try driver.variantIndexStorePaths(driver.builds()), Set(stores))
            XCTAssertEqual(Set(stores).count, 2)
        }

        // MARK: - Coverage

        func testEveryVariant_strictCoverageExpectsThePlatformsOfTheVariantsThatBuildEachTarget() throws {
            let shell = RecordingShellMock()
            let (driver, _, project) = try makeDriver(everyVariant(), shell: shell)

            let coverage = try coveragePlatforms(driver: driver, project: project)

            XCTAssertEqual(coverage, [
                "App-iOS": [.iOS],
                "App-macOS": [.macOS],
                "Core": [.iOS, .macOS],
                "Tools": [.macOS],
            ])
        }

        func testEveryVariant_strictCoverageOfADependencyFollowsTheSchemesThatBuildIt() throws {
            let shell = RecordingShellMock()
            let (driver, _, project) = try makeDriver(everyVariant(platforms: ["iOS", "macOS"]), shell: shell, schemes: ["App-macOS"])

            let coverage = try coveragePlatforms(driver: driver, project: project)

            XCTAssertEqual(coverage["Core"], [.macOS])
            XCTAssertEqual(coverage["App-iOS"], [], "built by no variant")
        }

        // MARK: - Private

        private static let schemes = ["App-iOS", "App-macOS"]

        private func makeDriver(
            _ configuration: Configuration,
            shell: RecordingShellMock,
            schemes: Set<String> = Set(XcodeSchemeVariantTest.schemes)
        ) throws -> (XcodeProjectDriver, Xcodebuild, XcodeProject) {
            let cacheDirectory = root.appending("Cache")
            try FileManager.default.createDirectory(atPath: cacheDirectory.string, withIntermediateDirectories: true)
            let xcodebuild = Xcodebuild(shell: shell, logger: logger, cacheDirectory: cacheDirectory)
            let project = try loadProject(shell: shell)
            let driver = XcodeProjectDriver(logger: logger, configuration: configuration, xcodebuild: xcodebuild, project: project, schemes: schemes)
            return (driver, xcodebuild, project)
        }

        private func loadProject(shell: RecordingShellMock) throws -> XcodeProject {
            var loadedProjectPaths: Set<FilePath> = []
            return try XcodeProject(
                path: projectPath,
                loadedProjectPaths: &loadedProjectPaths,
                xcodebuild: Xcodebuild(shell: shell, logger: logger),
                shell: shell,
                logger: logger
            )
        }

        private func everyVariant(platforms: [String] = []) -> Configuration {
            var configuration = Configuration()
            configuration.everyVariant = true
            configuration.variantPlatforms = platforms
            return configuration
        }

        private func names(_ targets: Set<XcodeTarget>) -> [String] {
            targets.map(\.name).sorted()
        }

        /// Each build as `scheme: destination`, checking that it builds in the DerivedData folder of its variant,
        /// shared by every scheme.
        private func builtSchemes(_ shell: RecordingShellMock, xcodebuild: Xcodebuild, project: XcodeProject) throws -> [String] {
            try shell.buildCommands.map { command in
                let scheme = try XCTUnwrap(command.firstIndex(of: "-scheme").map { command[$0 + 1] })
                let destination = try XCTUnwrap(command.firstIndex(of: "-destination").map { command[$0 + 1] })
                let derivedData = try XCTUnwrap(command.firstIndex(of: "-derivedDataPath").map { command[$0 + 1] })
                let variantArguments = Array(command.drop { $0 != "-destination" })
                let expected = try xcodebuild.derivedDataPath(for: project, schemes: Self.schemes, buildArguments: variantArguments)
                XCTAssertEqual(derivedData, expected.string)
                return "\(scheme): \(destination)"
            }
        }

        private func coveragePlatforms(driver: XcodeProjectDriver, project: XcodeProject) throws -> [String: Set<IndexPlatform>] {
            let builds = try driver.builds()
            let targets = Dictionary(uniqueKeysWithValues: project.targets.map { ($0.name, $0) })
            return XcodeProjectDriver.coverageTargets(of: targets) { driver.variantPlatforms(of: $0, builds: builds) }.mapValues(\.platforms)
        }

        private func writeScheme(target: String, in folder: String) throws {
            let index = try XCTUnwrap(Self.targetSpecs.firstIndex { $0.name == target })
            let directory = projectPath.appending(folder)
            try FileManager.default.createDirectory(atPath: directory.string, withIntermediateDirectories: true)
            try """
            <?xml version="1.0" encoding="UTF-8"?>
            <Scheme LastUpgradeVersion = "1600" version = "1.7">
               <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
                  <BuildActionEntries>
                     <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
                        <BuildableReference
                           BuildableIdentifier = "primary"
                           BlueprintIdentifier = "\(Self.identifier(1, index))"
                           BuildableName = "\(target).app"
                           BlueprintName = "\(target)"
                           ReferencedContainer = "container:Sample.xcodeproj">
                        </BuildableReference>
                     </BuildActionEntry>
                  </BuildActionEntries>
               </BuildAction>
            </Scheme>
            """.write(toFile: directory.appending("\(target).xcscheme").string, atomically: true, encoding: .utf8)
        }

        private static func identifier(_ kind: Int, _ index: Int) -> String {
            String(format: "%012X%012X", kind, index)
        }

        /// A project file with the targets of `targetSpecs`, their supported platforms and their dependencies.
        private static func projectFile() -> String {
            let targetIDs = targetSpecs.indices.map { identifier(1, $0) }
            var objects = [
                "\(identifier(0, 0)) = {isa = PBXProject; attributes = {}; buildConfigurationList = \(identifier(0, 1)); " +
                    "compatibilityVersion = \"Xcode 14.0\"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, ); " +
                    "mainGroup = \(identifier(0, 2)); projectDirPath = \"\"; projectRoot = \"\"; targets = (\(targetIDs.joined(separator: ", ")), ); };",
                "\(identifier(0, 1)) = {isa = XCConfigurationList; buildConfigurations = (\(identifier(0, 3)), ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };",
                "\(identifier(0, 2)) = {isa = PBXGroup; children = (); sourceTree = \"<group>\"; };",
                "\(identifier(0, 3)) = {isa = XCBuildConfiguration; buildSettings = {}; name = Debug; };",
            ]
            for (index, spec) in targetSpecs.enumerated() {
                let dependencyIDs = spec.dependencies.indices.map { identifier(4 + index, $0) }
                objects += [
                    "\(identifier(1, index)) = {isa = PBXNativeTarget; buildConfigurationList = \(identifier(2, index)); buildPhases = (); buildRules = (); " +
                        "dependencies = (\(dependencyIDs.map { "\($0), " }.joined())); name = \"\(spec.name)\"; productName = \"\(spec.name)\"; " +
                        "productType = \"com.apple.product-type.application\"; };",
                    "\(identifier(2, index)) = {isa = XCConfigurationList; buildConfigurations = (\(identifier(3, index)), ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };",
                    "\(identifier(3, index)) = {isa = XCBuildConfiguration; buildSettings = {SUPPORTED_PLATFORMS = \"\(spec.platforms)\"; }; name = Debug; };",
                ]
                for (dependencyIndex, target) in spec.dependencies.enumerated() {
                    objects.append("\(identifier(4 + index, dependencyIndex)) = {isa = PBXTargetDependency; target = \(identifier(1, target)); };")
                }
            }
            return """
            // !$*UTF8*$!
            {
            archiveVersion = 1;
            classes = {
            };
            objectVersion = 56;
            objects = {
            \(objects.joined(separator: "\n"))
            };
            rootObject = \(identifier(0, 0));
            }
            """
        }
    }
#endif

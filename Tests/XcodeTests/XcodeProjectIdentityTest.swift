#if os(macOS)
    import Configuration
    import Foundation
    import Logger
    @testable import ProjectDrivers
    import Shared
    import SystemPackage
    @testable import TestShared
    @testable import XcodeSupport
    import XCTest

    /// A workspace whose two projects, `A/SyncedGroupProject.xcodeproj` and `B/SyncedGroupProject.xcodeproj`, have
    /// targets of the same names.
    final class XcodeProjectIdentityTest: XCTestCase {
        private let logger = Logger(quiet: true, verbose: false, colorMode: .never)
        private var root: FilePath!

        override func setUpWithError() throws {
            try super.setUpWithError()
            let fileManager = FileManager.default
            root = FilePath(fileManager.temporaryDirectory.path).appending("XcodeProjectIdentityTest-\(UUID().uuidString)")
            try fileManager.createDirectory(atPath: root.string, withIntermediateDirectories: true)

            for copy in ["A", "B"] {
                try fileManager.copyItem(atPath: SyncedGroupProjectRoot.string, toPath: root.appending(copy).string)
            }

            let workspace = root.appending("W.xcworkspace")
            try fileManager.createDirectory(atPath: workspace.string, withIntermediateDirectories: true)
            try """
            <?xml version="1.0" encoding="UTF-8"?>
            <Workspace version = "1.0">
               <FileRef location = "group:A/SyncedGroupProject.xcodeproj"></FileRef>
               <FileRef location = "group:B/SyncedGroupProject.xcodeproj"></FileRef>
            </Workspace>
            """.write(toFile: workspace.appending("contents.xcworkspacedata").string, atomically: true, encoding: .utf8)
        }

        override func tearDownWithError() throws {
            try FileManager.default.removeItem(atPath: root.string)
            root = nil
            try super.tearDownWithError()
        }

        func testProjectReferencedThroughDifferentPaths_isEqualWithTheSameHash() throws {
            let direct = try loadProject(at: root.appending("A/SyncedGroupProject.xcodeproj"))
            let indirect = try loadProject(at: root.appending("B/../A/SyncedGroupProject.xcodeproj"))

            XCTAssertEqual(direct, indirect)
            XCTAssertEqual(direct.hashValue, indirect.hashValue)
            XCTAssertEqual(direct.targets, indirect.targets)
        }

        func testWorkspace_keepsTargetsOfTheSameNameFromDistinctProjects() throws {
            let workspace = try loadWorkspace()
            let appProjects = workspace.targets.filter { $0.name == "App" }.map { $0.project.path.relativeTo(root).string }

            XCTAssertEqual(appProjects.sorted(), ["A/SyncedGroupProject.xcodeproj", "B/SyncedGroupProject.xcodeproj"])
        }

        func testScannedTargets_qualifyANameSharedByDistinctProjects() throws {
            let workspace = try loadWorkspace()
            try workspace.targets.forEach { try $0.identifyFiles() }

            let scanned = XcodeProjectDriver.scannedTargets(of: workspace.targets, excluding: [], relativeTo: workspace.sourceRoot)
            let appKeys = scanned.filter { $0.value.name == "App" }

            XCTAssertEqual(
                appKeys.keys.sorted(),
                ["App (A/SyncedGroupProject.xcodeproj)", "App (B/SyncedGroupProject.xcodeproj)"]
            )
            XCTAssertEqual(appKeys["App (A/SyncedGroupProject.xcodeproj)"]?.project.path.relativeTo(root).string, "A/SyncedGroupProject.xcodeproj")
            XCTAssertEqual(XcodeProjectDriver.coverageTargets(of: scanned).count, scanned.count)
        }

        func testScannedTargets_excludeEveryTargetOfAnExcludedName() throws {
            let workspace = try loadWorkspace()
            try workspace.targets.forEach { try $0.identifyFiles() }

            let scanned = XcodeProjectDriver.scannedTargets(of: workspace.targets, excluding: ["App"], relativeTo: workspace.sourceRoot)

            XCTAssertFalse(scanned.isEmpty)
            XCTAssertFalse(scanned.values.contains { $0.name == "App" })
        }

        // MARK: - Private

        private func makeXcodebuild() -> (Xcodebuild, Shell) {
            let shell = ShellImpl(logger: logger)
            return (Xcodebuild(shell: shell, logger: logger, cacheDirectory: TestCacheDirectory.path), shell)
        }

        private func loadProject(at path: FilePath) throws -> XcodeProject {
            let (xcodebuild, shell) = makeXcodebuild()
            var loadedProjectPaths: Set<FilePath> = []
            return try XcodeProject(path: path, loadedProjectPaths: &loadedProjectPaths, xcodebuild: xcodebuild, shell: shell, logger: logger)
        }

        private func loadWorkspace() throws -> XcodeWorkspace {
            let (xcodebuild, shell) = makeXcodebuild()
            return try XcodeWorkspace(
                path: root.appending("W.xcworkspace"),
                xcodebuild: xcodebuild,
                configuration: Configuration(),
                logger: logger,
                shell: shell
            )
        }
    }
#endif

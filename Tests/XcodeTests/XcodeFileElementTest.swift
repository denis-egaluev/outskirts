import Foundation
import Logger
import Shared
import SystemPackage
@testable import TestShared
@testable import XcodeSupport
import XCTest

/// Projects written to a temporary directory, to resolve file elements that the fixture projects do not have.
final class XcodeFileElementTest: XCTestCase {
    private let logger = Logger(quiet: true, verbose: false, colorMode: .never)
    private var root: FilePath!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FilePath(FileManager.default.temporaryDirectory.path)
            .appending("XcodeFileElementTest-\(UUID().uuidString)")
            .lexicallyNormalized()
        try FileManager.default.createDirectory(atPath: root.string, withIntermediateDirectories: true)
        // The temporary directory may be a symbolic link, which the resolved paths go through as is.
        root = FilePath(URL(fileURLWithPath: root.string).resolvingSymlinksInPath().path)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(atPath: root.string)
        root = nil
        try super.tearDownWithError()
    }

    func testVariantGroupFiles_resolveEachVariantAgainstItsOwnSourceTree() throws {
        let absoluteVariant = root.appending("Elsewhere/de.lproj/LaunchScreen.storyboard")
        try createFiles([
            "Resources/Base.lproj/LaunchScreen.storyboard",
            "Resources/fr.lproj/LaunchScreen.storyboard",
            "Resources/Base.lproj/Main.storyboard",
            "Elsewhere/de.lproj/LaunchScreen.storyboard",
        ])
        let project = try loadProject(
            objects: [
                "RESOURCES": #"{isa = PBXGroup; children = (LAUNCH, MAIN_SB); path = Resources; sourceTree = "<group>"; }"#,
                "LAUNCH": #"{isa = PBXVariantGroup; children = (LAUNCH_BASE, LAUNCH_FR, LAUNCH_DE, LAUNCH_IT); name = LaunchScreen.storyboard; sourceTree = "<group>"; }"#,
                "LAUNCH_BASE": #"{isa = PBXFileReference; lastKnownFileType = file.storyboard; name = Base; path = Resources/Base.lproj/LaunchScreen.storyboard; sourceTree = SOURCE_ROOT; }"#,
                "LAUNCH_FR": #"{isa = PBXFileReference; lastKnownFileType = file.storyboard; name = fr; path = fr.lproj/LaunchScreen.storyboard; sourceTree = "<group>"; }"#,
                "LAUNCH_DE": #"{isa = PBXFileReference; lastKnownFileType = file.storyboard; name = de; path = "\#(absoluteVariant.string)"; sourceTree = "<absolute>"; }"#,
                "LAUNCH_IT": #"{isa = PBXFileReference; lastKnownFileType = file.storyboard; name = it; path = it.lproj/LaunchScreen.storyboard; sourceTree = BUILT_PRODUCTS_DIR; }"#,
                "MAIN_SB": #"{isa = PBXVariantGroup; children = (MAIN_BASE); name = Main.storyboard; sourceTree = "<group>"; }"#,
                "MAIN_BASE": #"{isa = PBXFileReference; lastKnownFileType = file.storyboard; name = Base; path = Base.lproj/Main.storyboard; sourceTree = "<group>"; }"#,
            ],
            mainGroupChildren: ["RESOURCES"],
            resources: ["LAUNCH", "MAIN_SB"]
        )
        let target = try XCTUnwrap(project.targets.first)

        try target.identifyFiles()

        XCTAssertEqual(target.files(kind: .interfaceBuilder), [
            root.appending("Resources/Base.lproj/LaunchScreen.storyboard"),
            root.appending("Resources/fr.lproj/LaunchScreen.storyboard"),
            absoluteVariant,
            root.appending("Resources/Base.lproj/Main.storyboard"),
        ])
    }

    func testFileElementsOutsideAnyGroup_areSkippedWithAWarning() throws {
        try createFiles(["Sources/App.swift", "Orphan.swift"])
        let project = try loadProject(
            objects: [
                "SOURCES": #"{isa = PBXGroup; children = (APP_SWIFT); path = Sources; sourceTree = "<group>"; }"#,
                "APP_SWIFT": #"{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = App.swift; sourceTree = "<group>"; }"#,
                "ORPHAN_SWIFT": #"{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Orphan.swift; sourceTree = "<group>"; }"#,
                "ORPHAN_PROJECT": #"{isa = PBXFileReference; lastKnownFileType = "wrapper.pb-project"; path = Other.xcodeproj; sourceTree = "<group>"; }"#,
            ],
            mainGroupChildren: ["SOURCES"],
            sources: ["APP_SWIFT", "ORPHAN_SWIFT"]
        )
        let target = try XCTUnwrap(project.targets.first)

        try target.identifyFiles()

        XCTAssertEqual(target.swiftSourceFiles, [root.appending("Sources/App.swift")])
        let orphan = try XCTUnwrap(project.xcodeProject.pbxproj.fileReferences.first { $0.path == "Orphan.swift" })
        var warnings: [String] = []
        XCTAssertNil(project.fileElements.path(of: orphan) { warnings.append($0) })
        XCTAssertEqual(warnings.count, 1)
        let warning = warnings.first ?? ""
        XCTAssertTrue(warning.contains("'Orphan.swift'"), warning)
        XCTAssertTrue(warning.contains("'Fixture'"), warning)
    }

    // MARK: - Private

    private func createFiles(_ paths: [String]) throws {
        for path in paths {
            let filePath = root.appending(path)
            try FileManager.default.createDirectory(atPath: filePath.removingLastComponent().string, withIntermediateDirectories: true)
            XCTAssertTrue(FileManager.default.createFile(atPath: filePath.string, contents: Data()))
        }
    }

    /// Writes and loads `Fixture.xcodeproj` at the root, with one application target whose build phases hold build
    /// files of the given file elements. The object identifiers are names, which the project file format allows.
    private func loadProject(
        objects: [String: String],
        mainGroupChildren: [String],
        sources: [String] = [],
        resources: [String] = []
    ) throws -> XcodeProject {
        let buildFiles = (sources + resources).map { "\($0)_BUILD_FILE = {isa = PBXBuildFile; fileRef = \($0); };" }
        let objectLines = objects.sorted { $0.key < $1.key }.map { "\($0.key) = \($0.value);" } + buildFiles
        let list = { (elements: [String]) in elements.map { "\($0)_BUILD_FILE" }.joined(separator: ", ") }
        let contents = """
        // !$*UTF8*$!
        {
            archiveVersion = 1;
            classes = {};
            objectVersion = 56;
            objects = {
                \(objectLines.joined(separator: "\n        "))
                MAIN_GROUP = {isa = PBXGroup; children = (\(mainGroupChildren.joined(separator: ", "))); sourceTree = "<group>"; };
                SOURCES_PHASE = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (\(list(sources))); runOnlyForDeploymentPostprocessing = 0; };
                RESOURCES_PHASE = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (\(list(resources))); runOnlyForDeploymentPostprocessing = 0; };
                APP = {isa = PBXNativeTarget; buildConfigurationList = APP_CONFIGURATIONS; buildPhases = (SOURCES_PHASE, RESOURCES_PHASE); buildRules = (); dependencies = (); name = App; productName = App; productType = "com.apple.product-type.application"; };
                APP_CONFIGURATIONS = {isa = XCConfigurationList; buildConfigurations = (APP_DEBUG); defaultConfigurationIsVisible = 0; };
                APP_DEBUG = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Debug; };
                PROJECT_CONFIGURATIONS = {isa = XCConfigurationList; buildConfigurations = (PROJECT_DEBUG); defaultConfigurationIsVisible = 0; };
                PROJECT_DEBUG = {isa = XCBuildConfiguration; buildSettings = {}; name = Debug; };
                PROJECT = {isa = PBXProject; attributes = {}; buildConfigurationList = PROJECT_CONFIGURATIONS; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = MAIN_GROUP; projectDirPath = ""; projectRoot = ""; targets = (APP); };
            };
            rootObject = PROJECT;
        }
        """
        let projectPath = root.appending("Fixture.xcodeproj")
        try FileManager.default.createDirectory(atPath: projectPath.string, withIntermediateDirectories: true)
        try contents.write(toFile: projectPath.appending("project.pbxproj").string, atomically: true, encoding: .utf8)

        let shell = ShellImpl(logger: logger)
        let xcodebuild = Xcodebuild(shell: shell, logger: logger, cacheDirectory: TestCacheDirectory.path)
        var loadedProjectPaths: Set<FilePath> = []

        return try XcodeProject(
            path: projectPath,
            loadedProjectPaths: &loadedProjectPaths,
            xcodebuild: xcodebuild,
            shell: shell,
            logger: logger
        )
    }
}

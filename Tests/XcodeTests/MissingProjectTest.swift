#if os(macOS)
    import Configuration
    import Foundation
    import Logger
    import ProjectDrivers
    import Shared
    import SystemPackage
    import XcodeSupport
    import XCTest

    final class MissingProjectTest: XCTestCase {
        private final class RecordingShell: Shell, @unchecked Sendable {
            private(set) var commands: [[String]] = []

            func exec(_ args: [String]) throws -> String {
                commands.append(args)
                return ""
            }
        }

        private let logger = Logger(quiet: true, verbose: false, colorMode: .never)
        private let missing = FilePath("/nonexistent-outskirts-test/Missing.xcodeproj")

        func testMissingProjectNamesThePathBeforeAnyWork() {
            let shell = RecordingShell()
            let configuration = Configuration()
            configuration.schemes = ["App"]

            XCTAssertThrowsError(try XcodeProjectDriver(projectPath: missing, configuration: configuration, shell: shell, logger: logger)) { error in
                XCTAssertEqual(error.localizedDescription, "No Xcode project or workspace found at \(missing.string).")
            }
            XCTAssertEqual(shell.commands, [])
        }

        func testMissingProjectLoadedDirectlyNamesThePath() {
            var loaded: Set<FilePath> = []
            let shell = RecordingShell()

            XCTAssertThrowsError(try XcodeProject(
                path: missing,
                loadedProjectPaths: &loaded,
                xcodebuild: Xcodebuild(shell: shell, logger: logger),
                shell: shell,
                logger: logger
            )) { error in
                XCTAssertEqual(error.localizedDescription, "No Xcode project or workspace found at \(missing.string).")
            }
        }
    }
#endif

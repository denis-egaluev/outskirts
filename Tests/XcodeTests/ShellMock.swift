import Foundation
import Shared

struct ShellMock: Shell {
    let output: String

    func exec(_: [String]) throws -> String {
        output
    }
}

/// Records the commands it runs and answers them as `xcodebuild -version` would, or `-showBuildSettings` with the
/// `buildSettings` of the scheme, else no target; a command containing the argument `failing` fails as xcodebuild does for a destination it cannot find.
final class RecordingShellMock: Shell, @unchecked Sendable {
    private(set) var commands: [[String]] = []
    private let failing: String?
    private let buildSettings: [String: String]

    init(failing: String? = nil, buildSettings: [String: String] = [:]) {
        self.failing = failing
        self.buildSettings = buildSettings
    }

    var showBuildSettingsCommands: [[String]] {
        commands.filter { $0.contains("-showBuildSettings") }
    }

    var buildCommands: [[String]] {
        commands.filter { $0.contains("build-for-testing") }
    }

    func exec(_ args: [String]) throws -> String {
        commands.append(args)
        if let failing, args.contains(failing) {
            throw PeripheryError.shellCommandFailed(cmd: args, status: 70, output: "xcodebuild: error: Unable to find a destination matching '\(failing)'")
        }
        if args.contains("-showBuildSettings") {
            let scheme = args.firstIndex(of: "-scheme").map { args[$0 + 1] } ?? ""
            return buildSettings[scheme] ?? "[]"
        }
        return "Xcode 0.0"
    }
}

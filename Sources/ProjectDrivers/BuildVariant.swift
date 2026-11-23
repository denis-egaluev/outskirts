import Indexer

/// One build of the project among those `every_variant` makes: a platform, a build configuration and a set of
/// compilation conditions.
struct BuildVariant: Hashable, CustomStringConvertible, Sendable {
    enum Platform: Hashable, CustomStringConvertible, Sendable {
        /// An Xcode build for any device of a platform; Mac Catalyst builds for this Mac.
        case device(IndexPlatform)
        /// An Xcode build for any simulator of a platform.
        case simulator(IndexPlatform)
        /// A Swift package build for the platform the tool runs on.
        case host
        /// A Swift package build for a target triple.
        case triple(String)

        private static let names: [String: Platform] = [
            "ios": .device(.iOS),
            "iphoneos": .device(.iOS),
            "iossimulator": .simulator(.iOS),
            "iphonesimulator": .simulator(.iOS),
            "macos": .device(.macOS),
            "macosx": .device(.macOS),
            "maccatalyst": .device(.macCatalyst),
            "tvos": .device(.tvOS),
            "appletvos": .device(.tvOS),
            "tvossimulator": .simulator(.tvOS),
            "appletvsimulator": .simulator(.tvOS),
            "watchos": .device(.watchOS),
            "watchossimulator": .simulator(.watchOS),
            "watchsimulator": .simulator(.watchOS),
            "visionos": .device(.visionOS),
            "xros": .device(.visionOS),
            "visionossimulator": .simulator(.visionOS),
            "xrsimulator": .simulator(.visionOS),
            "driverkit": .device(.driverKit),
        ]

        /// The platform of a `variant_platforms` entry, such as `iOS`, `iOS Simulator`, `Mac Catalyst` or an SDK
        /// name such as `iphonesimulator`, ignoring case, spaces and dashes; `nil` for a name it does not know.
        init?(name: String) {
            let key = name.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
            guard let platform = Self.names[key] else { return nil }

            self = platform
        }

        /// The platform of an SDK name of the `SDKROOT` or `SUPPORTED_PLATFORMS` build settings, such as `iphoneos`
        /// or `iphonesimulator`; `nil` for a name it does not know, such as `auto`.
        init?(sdk: String) {
            guard IndexPlatform(sdk: sdk) != nil else { return nil }

            self.init(name: sdk)
        }

        /// The platform the index units of this build are compiled for; `nil` for a triple of an unknown system.
        var indexPlatform: IndexPlatform? {
            switch self {
            case let .device(platform), let .simulator(platform): platform
            case .host: .host
            case let .triple(triple): IndexPlatform(triple: triple)
            }
        }

        /// The `-destination` of xcodebuild; `nil` for a Swift package build.
        var destination: String? {
            switch self {
            case .device(.macCatalyst): "platform=macOS,variant=Mac Catalyst"
            case let .device(platform): "generic/platform=\(platform.name)"
            case let .simulator(platform): "generic/platform=\(platform.name) Simulator"
            case .host, .triple: nil
            }
        }

        var description: String {
            switch self {
            case let .device(platform): platform.name
            case let .simulator(platform): "\(platform.name) Simulator"
            case .host: "host"
            case let .triple(triple): triple
            }
        }
    }

    let platform: Platform
    let configuration: String
    let conditions: [String]

    init(platform: Platform, configuration: String, conditions: [String] = []) {
        self.platform = platform
        self.configuration = configuration
        self.conditions = conditions
    }

    /// Whether the configuration is the Debug one, which already compiles with testability.
    var isDebug: Bool {
        configuration.lowercased() == "debug"
    }

    /// The xcodebuild arguments that select this variant. Configurations other than Debug compile with testability, so
    /// that the index of their internal declarations matches the Debug one.
    var xcodebuildArguments: [String] {
        var arguments: [String] = []
        if let destination = platform.destination {
            arguments += ["-destination", destination]
        }
        arguments += ["-configuration", configuration]
        if !conditions.isEmpty {
            arguments.append((["SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited)"] + conditions).joined(separator: " "))
        }
        if !isDebug {
            arguments.append("ENABLE_TESTABILITY=YES")
        }
        return arguments
    }

    /// The `swift build` arguments that select this variant. The release configuration compiles with testability, as
    /// the Xcode configurations other than Debug do.
    var swiftBuildArguments: [String] {
        var arguments: [String] = []
        if case let .triple(triple) = platform {
            arguments += ["--triple", triple]
        }
        arguments += ["-c", configuration.lowercased()]
        arguments += conditions.flatMap { ["-Xswiftc", "-D\($0)"] }
        if !isDebug {
            arguments += ["-Xswiftc", "-enable-testing"]
        }
        return arguments
    }

    var description: String {
        ([platform.description, configuration] + (conditions.isEmpty ? [] : [conditions.joined(separator: " ")]))
            .joined(separator: " · ")
    }
}

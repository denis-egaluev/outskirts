import Configuration
import Foundation
import Indexer
import Shared

/// Turns the `every_variant` settings into the builds to make. Without `every_variant`, there is no variant and the
/// project is built once, as before.
struct BuildVariantResolver {
    struct Resolution: Equatable, Sendable {
        let variants: [BuildVariant]
        let warnings: [String]
        /// The schemes that build each variant of an Xcode project.
        var schemes: [BuildVariant: [String]] = [:]
    }

    /// Options of `build_arguments` that choose what each variant sets itself, matched ignoring leading dashes and
    /// any `=value`.
    static let variantOptions: Set<String> = ["destination", "sdk", "configuration", "triple", "c"]

    /// Options whose next argument goes to another tool and is not an option of the build.
    static let forwardingOptions: Set<String> = ["-Xswiftc", "-Xcc", "-Xcxx", "-Xlinker", "-Xbuild-tools-swiftc"]

    private let configuration: Configuration

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    /// The settings, set along `every_variant`, that read the index of a build made elsewhere instead of building the
    /// variants.
    var prebuiltIndexSettings: [String] {
        guard configuration.everyVariant else { return [] }

        return [
            configuration.indexStorePath.isEmpty ? nil : "index_store_path",
            configuration.derivedDataPath.isEmpty ? nil : "derived_data_path",
            configuration.skipBuild ? "skip_build" : nil,
        ].compactMap(\.self)
    }

    /// Throws a usage error for a setting that `every_variant` cannot honour.
    func validate() throws {
        guard configuration.everyVariant else { return }

        if configuration.genericProjectConfig != nil {
            throw PeripheryError.usageError(
                "'every_variant' cannot be used with 'generic_project_config': outskirts does not build a generic project. " +
                    "Build each variant yourself and pass their index stores with 'index_store_path'."
            )
        }

        if let argument = Self.variantArgument(in: configuration.buildArguments) {
            throw PeripheryError.usageError(
                "'build_arguments' cannot contain '\(argument)' with 'every_variant': each variant sets its own destination, SDK, configuration or triple. " +
                    "Use 'variant_platforms', 'variant_configurations' or 'variant_triples' instead."
            )
        }

        _ = try explicitPlatforms()
        _ = try conditionSets()

        if let configurationName = configuration.variantConfigurations.first(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            throw PeripheryError.usageError("'variant_configurations' contains an empty configuration name '\(configurationName)'.")
        }

        if let triple = configuration.variantTriples.first(where: { $0.isEmpty || $0.contains(where: \.isWhitespace) }) {
            throw PeripheryError.usageError("'variant_triples' contains an invalid target triple '\(triple)'.")
        }
    }

    /// The SDK names of the targets of each scheme, completed with those xcodebuild resolves for the schemes whose
    /// targets have SDKs the project does not tell, e.g. set by an `.xcconfig` file: `resolve` runs once per such
    /// scheme and is not run when every SDK is known.
    static func resolvingUnknownSDKs(
        schemes: [String],
        schemeTargetSDKs: [String: [String: Set<String>]],
        projectTargetSDKs: [String: Set<String>],
        resolve: (String) throws -> [String: Set<String>]
    ) throws -> [String: [String: Set<String>]] {
        var result = schemeTargetSDKs
        for scheme in unique(schemes).sorted() {
            let known = schemeTargetSDKs[scheme]
            let targetSDKs = known ?? projectTargetSDKs
            guard targetSDKs.isEmpty || targetSDKs.values.contains(where: \.isEmpty) else { continue }

            let resolved = try resolve(scheme)
            if let known {
                result[scheme] = known.reduce(into: [:]) { sdks, target in
                    sdks[target.key] = target.value.isEmpty ? resolved[target.key, default: []] : target.value
                }
            } else if !resolved.isEmpty {
                result[scheme] = resolved
            }
        }
        return result
    }

    /// The variants of an Xcode project: the platforms of `variant_platforms`, else those the targets of the schemes
    /// support, times the configurations of `variant_configurations`, else Debug, plus one variant per set of
    /// `variant_conditions` on the first platform of each scheme and the first configuration. Each scheme builds only
    /// the variants of the platforms its targets support; a scheme whose platforms are unknown builds every variant.
    /// - Parameters:
    ///   - schemes: the schemes to build.
    ///   - schemeTargetSDKs: for each scheme whose targets are known, the SDK names each target it builds supports, by
    ///     target name.
    ///   - projectTargetSDKs: the SDK names each scanned target supports, by target name, which the schemes of unknown
    ///     targets build.
    ///   - projectConfigurations: the build configurations of the project, which `all` stands for.
    func xcodeVariants(
        schemes: [String],
        schemeTargetSDKs: [String: [String: Set<String>]],
        projectTargetSDKs: [String: Set<String>],
        projectConfigurations: [String]
    ) throws -> Resolution {
        guard configuration.everyVariant else { return Resolution(variants: [], warnings: []) }

        try validate()

        var warnings: [String] = []
        var platforms = try explicitPlatforms()
        if platforms.isEmpty {
            let builtTargetSDKs = schemes.reduce(into: [String: Set<String>]()) { result, scheme in
                result.merge(schemeTargetSDKs[scheme] ?? projectTargetSDKs) { $0.union($1) }
            }
            let detected = Self.detectedPlatforms(targetSDKs: builtTargetSDKs)
            platforms = detected.platforms

            let unknownWarning = detected.unknownTargets.isEmpty ? nil :
                "every_variant cannot tell the platforms of \(detected.unknownTargets.joined(separator: ", ")) from the project " +
                "(SDK unknown or set by an .xcconfig file): list the platforms to build with 'variant_platforms'."
            guard !platforms.isEmpty else {
                let message = "every_variant found no platform supported by the targets: list the platforms to build with " +
                    "'variant_platforms', e.g. 'iOS', 'iOS Simulator', 'macOS' or 'Mac Catalyst'."
                throw PeripheryError.usageError([message, unknownWarning].compactMap(\.self).joined(separator: "\n"))
            }

            if let unknownWarning {
                warnings.append(unknownWarning)
            }
        }

        var schemePlatforms: [String: [BuildVariant.Platform]] = [:]
        var skippedSchemes: [String] = []
        for scheme in Self.unique(schemes).sorted() {
            let supported = schemeTargetSDKs[scheme].map { Self.knownPlatforms(targetSDKs: $0) } ?? []
            let kept = supported.isEmpty ? platforms : platforms.filter { Self.supports(supported, $0) }
            if kept.isEmpty {
                skippedSchemes.append(scheme)
            } else {
                schemePlatforms[scheme] = kept
            }
        }

        let platformList = platforms.map(\.description).joined(separator: ", ")
        guard !schemePlatforms.isEmpty else {
            throw PeripheryError.usageError(
                "every_variant has no variant to build: the targets of the schemes support none of the platforms \(platformList) of 'variant_platforms'."
            )
        }

        if !skippedSchemes.isEmpty {
            warnings.append(
                "every_variant does not build \(skippedSchemes.joined(separator: ", ")): its targets support none of the platforms \(platformList) of 'variant_platforms'."
            )
        }

        let configurations = try xcodeConfigurations(projectConfigurations: projectConfigurations)
        let builtPlatforms = platforms.filter { platform in schemePlatforms.values.contains { $0.contains(platform) } }
        let firstPlatforms = builtPlatforms.filter { platform in schemePlatforms.values.contains { $0.first == platform } }
        var schemesByVariant: [BuildVariant: [String]] = [:]
        var variants: [BuildVariant] = []

        for platform in builtPlatforms {
            let builders = schemePlatforms.filter { $0.value.contains(platform) }.keys.sorted()
            for configurationName in configurations {
                let variant = BuildVariant(platform: platform, configuration: configurationName)
                variants.append(variant)
                schemesByVariant[variant] = builders
            }
        }
        for conditions in try conditionSets() {
            for platform in firstPlatforms {
                let variant = BuildVariant(platform: platform, configuration: configurations[0], conditions: conditions)
                variants.append(variant)
                schemesByVariant[variant] = schemePlatforms.filter { $0.value.first == platform }.keys.sorted()
            }
        }

        return Resolution(variants: variants, warnings: warnings, schemes: schemesByVariant)
    }

    /// The variants of a Swift package: the triples of `variant_triples`, else the host, times the configurations of
    /// `variant_configurations` (`debug`, `release` or `all`), else debug, plus one variant per set of
    /// `variant_conditions` on the first triple and configuration.
    func swiftPackageVariants() throws -> Resolution {
        guard configuration.everyVariant else { return Resolution(variants: [], warnings: []) }

        try validate()

        let triples = Self.unique(configuration.variantTriples)
        let platforms: [BuildVariant.Platform] = triples.isEmpty ? [.host] : triples.map { .triple($0) }
        let configurations = try swiftPackageConfigurations()
        return try Resolution(variants: variants(platforms: platforms, configurations: configurations), warnings: [])
    }

    // MARK: - Private

    private func variants(platforms: [BuildVariant.Platform], configurations: [String]) throws -> [BuildVariant] {
        let base = platforms.flatMap { platform in
            configurations.map { BuildVariant(platform: platform, configuration: $0) }
        }
        let conditional = try conditionSets().map {
            BuildVariant(platform: platforms[0], configuration: configurations[0], conditions: $0)
        }
        return base + conditional
    }

    private func explicitPlatforms() throws -> [BuildVariant.Platform] {
        let platforms = try configuration.variantPlatforms.map { name in
            guard let platform = BuildVariant.Platform(name: name) else {
                throw PeripheryError.usageError(
                    "'variant_platforms' contains an unknown platform '\(name)'. " +
                        "Known platforms: iOS, iOS Simulator, macOS, Mac Catalyst, tvOS, tvOS Simulator, watchOS, watchOS Simulator, visionOS, visionOS Simulator, DriverKit."
                )
            }

            return platform
        }
        return Self.unique(platforms)
    }

    private func conditionSets() throws -> [[String]] {
        try configuration.variantConditions.map { entry in
            let names = entry.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
            guard !names.isEmpty else {
                throw PeripheryError.usageError("'variant_conditions' contains an empty set of conditions.")
            }

            if let name = names.first(where: { !Self.isConditionName($0) }) {
                throw PeripheryError.usageError(
                    "'variant_conditions' contains an invalid compilation condition '\(name)': a condition is a name made of letters, digits and underscores."
                )
            }
            return Self.unique(names)
        }
    }

    private func xcodeConfigurations(projectConfigurations: [String]) throws -> [String] {
        let requested = Self.unique(configuration.variantConfigurations)
        guard !requested.isEmpty else { return ["Debug"] }
        guard requested.contains(where: { $0.lowercased() == "all" }) else { return requested }

        let all = Self.unique(projectConfigurations)
        guard !all.isEmpty else {
            throw PeripheryError.usageError("'variant_configurations' is 'all', but the project lists no build configuration: list the configurations to build.")
        }

        return all
    }

    private func swiftPackageConfigurations() throws -> [String] {
        let requested = Self.unique(configuration.variantConfigurations.map { $0.lowercased() })
        guard !requested.isEmpty else { return ["debug"] }
        guard !requested.contains("all") else { return ["debug", "release"] }

        if let name = requested.first(where: { $0 != "debug" && $0 != "release" }) {
            throw PeripheryError.usageError("'variant_configurations' contains '\(name)', but a Swift package builds only the 'debug' and 'release' configurations.")
        }
        return requested
    }

    /// One platform per platform the targets support, sorted by name: the device build when a target supports the
    /// device SDK, else the simulator build. Also returns the targets whose platforms are unknown.
    static func detectedPlatforms(targetSDKs: [String: Set<String>]) -> (platforms: [BuildVariant.Platform], unknownTargets: [String]) {
        var simulatorOnly: [IndexPlatform: Bool] = [:]
        var unknownTargets: [String] = []

        for (target, sdks) in targetSDKs {
            let platforms = sdks.compactMap(BuildVariant.Platform.init(sdk:))
            if platforms.isEmpty || platforms.count < sdks.count {
                unknownTargets.append(target)
            }
            for platform in platforms {
                switch platform {
                case let .device(indexPlatform): simulatorOnly[indexPlatform] = false
                case let .simulator(indexPlatform): simulatorOnly[indexPlatform] = simulatorOnly[indexPlatform] ?? true
                case .host, .triple: break
                }
            }
        }

        let platforms = simulatorOnly.keys.sorted().map { platform -> BuildVariant.Platform in
            simulatorOnly[platform] == true ? .simulator(platform) : .device(platform)
        }
        return (platforms, unknownTargets.sorted())
    }

    /// The platforms of the SDKs the targets support, ignoring the SDKs it does not know.
    static func knownPlatforms(targetSDKs: [String: Set<String>]) -> Set<IndexPlatform> {
        targetSDKs.values.reduce(into: []) { result, sdks in
            result.formUnion(sdks.compactMap(IndexPlatform.init(sdk:)))
        }
    }

    /// Whether targets supporting these platforms build for `platform`: Mac Catalyst builds the iOS targets.
    static func supports(_ platforms: Set<IndexPlatform>, _ platform: BuildVariant.Platform) -> Bool {
        guard let indexPlatform = platform.indexPlatform else { return false }

        return platforms.contains(indexPlatform) || (indexPlatform == .macCatalyst && platforms.contains(.iOS))
    }

    /// The first argument of `arguments` that chooses a destination, an SDK, a configuration or a triple, skipping
    /// the arguments forwarded to the compiler or the linker.
    static func variantArgument(in arguments: [String]) -> String? {
        var isForwarded = false
        for argument in arguments {
            defer { isForwarded = forwardingOptions.contains(argument) }
            guard !isForwarded, argument.hasPrefix("-") else { continue }

            let option = argument.drop { $0 == "-" }.prefix { $0 != "=" }
            if option == "c" || (option.lowercased() != "c" && variantOptions.contains(option.lowercased())) {
                return argument
            }
        }
        return nil
    }

    private static func isConditionName(_ name: String) -> Bool {
        guard let first = name.first, first == "_" || (first.isASCII && first.isLetter) else { return false }

        return name.allSatisfy { $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }
}

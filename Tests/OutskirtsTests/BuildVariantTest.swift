import Configuration
import Indexer
@testable import ProjectDrivers
import Shared
import XCTest

final class BuildVariantTest: XCTestCase {
    private func configuration(_ change: (Configuration) -> Void = { _ in }) -> Configuration {
        let configuration = Configuration()
        configuration.everyVariant = true
        change(configuration)
        return configuration
    }

    /// The variants of a single scheme whose targets are unknown, which builds the targets of the project.
    private func xcodeVariants(
        _ configuration: Configuration,
        targetSDKs: [String: Set<String>] = ["App": ["iphoneos", "iphonesimulator"]],
        projectConfigurations: [String] = ["Debug", "Release"]
    ) throws -> BuildVariantResolver.Resolution {
        try BuildVariantResolver(configuration: configuration).xcodeVariants(
            schemes: ["App"],
            schemeTargetSDKs: [:],
            projectTargetSDKs: targetSDKs,
            projectConfigurations: projectConfigurations
        )
    }

    /// The variants of schemes whose targets are known, except those of `unknownSchemes`, which build the targets of
    /// the project.
    private func schemeVariants(
        _ configuration: Configuration,
        schemeTargetSDKs: [String: [String: Set<String>]] = BuildVariantTest.perPlatformSchemes,
        unknownSchemes: [String] = [],
        projectTargetSDKs: [String: Set<String>] = [:]
    ) throws -> BuildVariantResolver.Resolution {
        try BuildVariantResolver(configuration: configuration).xcodeVariants(
            schemes: Array(schemeTargetSDKs.keys) + unknownSchemes,
            schemeTargetSDKs: schemeTargetSDKs,
            projectTargetSDKs: projectTargetSDKs,
            projectConfigurations: ["Debug", "Release"]
        )
    }

    private static let perPlatformSchemes: [String: [String: Set<String>]] = [
        "App-iOS": ["App-iOS": ["iphoneos", "iphonesimulator"], "Widget-iOS": ["iphoneos", "iphonesimulator"]],
        "App-macOS": ["App-macOS": ["macosx"]],
    ]

    private func schemes(_ resolution: BuildVariantResolver.Resolution) -> [String] {
        resolution.variants.map { "\($0): \(resolution.schemes[$0, default: []].joined(separator: ", "))" }
    }

    private func assertUsageError(_ expression: @autoclosure () throws -> some Any, containing text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            guard case let PeripheryError.usageError(message) = error else {
                return XCTFail("Expected a usage error, got \(error)", file: file, line: line)
            }

            XCTAssertTrue(message.contains(text), "'\(message)' does not contain '\(text)'", file: file, line: line)
        }
    }

    // MARK: - Schemes

    func testEachPerPlatformSchemeBuildsOnlyThePlatformsOfItsTargets() throws {
        let resolution = try schemeVariants(configuration())

        XCTAssertEqual(schemes(resolution), ["iOS · Debug: App-iOS", "macOS · Debug: App-macOS"])
        XCTAssertEqual(resolution.warnings, [])
    }

    func testExplicitPlatformsAreFilteredPerScheme() throws {
        let resolution = try schemeVariants(configuration { $0.variantPlatforms = ["macOS", "iOS Simulator", "Mac Catalyst"] })

        XCTAssertEqual(schemes(resolution), [
            "macOS · Debug: App-macOS",
            "iOS Simulator · Debug: App-iOS",
            "Mac Catalyst · Debug: App-iOS",
        ])
        XCTAssertEqual(resolution.warnings, [])
    }

    func testSchemeSupportingNoListedPlatformIsSkippedWithAWarning() throws {
        let resolution = try schemeVariants(configuration { $0.variantPlatforms = ["iOS"] })

        XCTAssertEqual(schemes(resolution), ["iOS · Debug: App-iOS"])
        XCTAssertEqual(resolution.warnings.count, 1)
        XCTAssertTrue(resolution.warnings[0].contains("does not build App-macOS"), resolution.warnings[0])
    }

    func testNoSchemeSupportingTheListedPlatformsIsAnError() {
        assertUsageError(try schemeVariants(configuration { $0.variantPlatforms = ["tvOS"] }), containing: "tvOS")
    }

    func testMultiPlatformSchemeBuildsEveryPlatformOfItsTargets() throws {
        let resolution = try schemeVariants(
            configuration { $0.variantConditions = ["BETA"] },
            schemeTargetSDKs: ["App": ["App": ["iphoneos", "iphonesimulator", "macosx"]]]
        )

        XCTAssertEqual(schemes(resolution), ["iOS · Debug: App", "macOS · Debug: App", "iOS · Debug · BETA: App"])
    }

    func testConditionsBuildOnTheFirstPlatformOfEachScheme() throws {
        let resolution = try schemeVariants(configuration {
            $0.variantConfigurations = ["Release", "Debug"]
            $0.variantConditions = ["BETA"]
        })

        XCTAssertEqual(schemes(resolution), [
            "iOS · Release: App-iOS",
            "iOS · Debug: App-iOS",
            "macOS · Release: App-macOS",
            "macOS · Debug: App-macOS",
            "iOS · Release · BETA: App-iOS",
            "macOS · Release · BETA: App-macOS",
        ])
    }

    func testDetectionReadsOnlyTheTargetsOfTheSchemes() throws {
        let resolution = try schemeVariants(configuration(), schemeTargetSDKs: ["App-macOS": ["App-macOS": ["macosx"]]], projectTargetSDKs: [
            "App-macOS": ["macosx"],
            "App-iOS": ["iphoneos"],
        ])

        XCTAssertEqual(schemes(resolution), ["macOS · Debug: App-macOS"])
    }

    func testSchemeOfUnknownTargetsBuildsEveryVariant() throws {
        let resolution = try schemeVariants(
            configuration(),
            schemeTargetSDKs: ["App-iOS": ["App-iOS": ["iphoneos"]]],
            unknownSchemes: ["Packages"],
            projectTargetSDKs: ["App-iOS": ["iphoneos"], "App-macOS": ["macosx"]]
        )

        XCTAssertEqual(schemes(resolution), ["iOS · Debug: App-iOS, Packages", "macOS · Debug: Packages"])
    }

    func testSchemeOfTargetsOfUnknownPlatformsBuildsEveryListedPlatform() throws {
        let resolution = try schemeVariants(
            configuration { $0.variantPlatforms = ["iOS", "macOS"] },
            schemeTargetSDKs: ["App-iOS": ["App-iOS": ["iphoneos"]], "Configured": ["Configured": []]]
        )

        XCTAssertEqual(schemes(resolution), ["iOS · Debug: App-iOS, Configured", "macOS · Debug: Configured"])
    }

    // MARK: - Resolution

    func testWithoutEveryVariantThereIsNoVariant() throws {
        let configuration = Configuration()
        configuration.variantPlatforms = ["iOS", "macOS"]
        configuration.buildArguments = ["-destination", "generic/platform=iOS"]

        XCTAssertEqual(try xcodeVariants(configuration).variants, [])
        XCTAssertEqual(try BuildVariantResolver(configuration: configuration).swiftPackageVariants().variants, [])
        XCTAssertNoThrow(try BuildVariantResolver(configuration: configuration).validate())
        XCTAssertEqual(BuildVariantResolver(configuration: configuration).prebuiltIndexSettings, [])
    }

    func testVariantsAreThePlatformsTimesTheConfigurations() throws {
        let resolution = try xcodeVariants(configuration {
            $0.variantPlatforms = ["iOS", "macOS"]
            $0.variantConfigurations = ["Debug", "Release"]
        })

        XCTAssertEqual(resolution.variants, [
            BuildVariant(platform: .device(.iOS), configuration: "Debug"),
            BuildVariant(platform: .device(.iOS), configuration: "Release"),
            BuildVariant(platform: .device(.macOS), configuration: "Debug"),
            BuildVariant(platform: .device(.macOS), configuration: "Release"),
        ])
        XCTAssertEqual(resolution.warnings, [])
    }

    func testDefaultConfigurationIsDebug() throws {
        let variants = try xcodeVariants(configuration { $0.variantPlatforms = ["macOS"] }).variants

        XCTAssertEqual(variants, [BuildVariant(platform: .device(.macOS), configuration: "Debug")])
    }

    func testAllConfigurationsAreTheProjectOnes() throws {
        let variants = try xcodeVariants(
            configuration {
                $0.variantPlatforms = ["macOS"]
                $0.variantConfigurations = ["all"]
            },
            projectConfigurations: ["Debug", "Beta", "Release"]
        ).variants

        XCTAssertEqual(variants.map(\.configuration), ["Debug", "Beta", "Release"])
    }

    func testAllConfigurationsWithoutProjectConfigurationsIsAnError() {
        let configuration = configuration {
            $0.variantPlatforms = ["macOS"]
            $0.variantConfigurations = ["all"]
        }

        assertUsageError(try xcodeVariants(configuration, projectConfigurations: []), containing: "'all'")
    }

    func testPlatformsDefaultToThoseTheTargetsSupport() throws {
        let resolution = try xcodeVariants(configuration(), targetSDKs: [
            "App": ["iphoneos", "iphonesimulator"],
            "Mac": ["macosx"],
            "Watch": ["watchsimulator"],
        ])

        XCTAssertEqual(resolution.variants.map(\.platform), [.device(.iOS), .device(.macOS), .simulator(.watchOS)])
        XCTAssertEqual(resolution.warnings, [])
    }

    func testTargetsOfUnknownPlatformsWarnAndSuggestAnExplicitList() throws {
        let resolution = try xcodeVariants(configuration(), targetSDKs: [
            "App": ["iphoneos"],
            "Configured": [],
            "Odd": ["auto"],
        ])

        XCTAssertEqual(resolution.variants.map(\.platform), [.device(.iOS)])
        XCTAssertEqual(resolution.warnings.count, 1)
        XCTAssertTrue(resolution.warnings[0].contains("Configured, Odd"))
        XCTAssertTrue(resolution.warnings[0].contains("variant_platforms"))
    }

    func testNoDetectedPlatformIsAnErrorNamingTheTargetsOfUnknownPlatforms() {
        assertUsageError(try xcodeVariants(configuration(), targetSDKs: ["Configured": []]), containing: "variant_platforms")
        assertUsageError(try xcodeVariants(configuration(), targetSDKs: ["Configured": []]), containing: "Configured")
        assertUsageError(try xcodeVariants(configuration(), targetSDKs: ["Configured": []]), containing: ".xcconfig")
    }

    // MARK: - Platforms resolved by xcodebuild

    private static let xcconfigSchemes: [String: [String: Set<String>]] = [
        "App-iOS": ["App-iOS": []],
        "App-macOS": ["App-macOS": [], "Shared": ["macosx"]],
    ]

    func testPlatformsSetByAnXcconfigAreResolvedPerScheme() throws {
        var resolved: [String] = []
        let targetSDKs = try BuildVariantResolver.resolvingUnknownSDKs(
            schemes: Array(Self.xcconfigSchemes.keys),
            schemeTargetSDKs: Self.xcconfigSchemes,
            projectTargetSDKs: [:]
        ) { scheme in
            resolved.append(scheme)
            return scheme == "App-iOS" ? ["App-iOS": ["iphoneos", "iphonesimulator"]] : ["App-macOS": ["macosx"], "Shared": ["macosx"]]
        }

        XCTAssertEqual(resolved, ["App-iOS", "App-macOS"])
        let resolution = try schemeVariants(configuration { $0.variantPlatforms = ["iOS", "macOS"] }, schemeTargetSDKs: targetSDKs)
        XCTAssertEqual(schemes(resolution), ["iOS · Debug: App-iOS", "macOS · Debug: App-macOS"])
        XCTAssertEqual(resolution.warnings, [])
        let detected = try schemeVariants(configuration(), schemeTargetSDKs: targetSDKs)
        XCTAssertEqual(schemes(detected), ["iOS · Debug: App-iOS", "macOS · Debug: App-macOS"])
    }

    func testKnownPlatformsAreNotResolvedAgain() throws {
        let targetSDKs = try BuildVariantResolver.resolvingUnknownSDKs(
            schemes: Array(Self.perPlatformSchemes.keys),
            schemeTargetSDKs: Self.perPlatformSchemes,
            projectTargetSDKs: [:]
        ) { scheme in
            XCTFail("resolved \(scheme)")
            return [:]
        }

        XCTAssertEqual(targetSDKs, Self.perPlatformSchemes)
    }

    func testPlatformsThatNothingResolvesAreAnErrorWithTheXcconfigHint() throws {
        let targetSDKs = try BuildVariantResolver.resolvingUnknownSDKs(
            schemes: Array(Self.xcconfigSchemes.keys),
            schemeTargetSDKs: ["App-iOS": ["App-iOS": []]],
            projectTargetSDKs: [:]
        ) { _ in [:] }

        assertUsageError(try schemeVariants(configuration(), schemeTargetSDKs: targetSDKs), containing: "found no platform")
        assertUsageError(try schemeVariants(configuration(), schemeTargetSDKs: targetSDKs), containing: "App-iOS")
        assertUsageError(try schemeVariants(configuration(), schemeTargetSDKs: targetSDKs), containing: ".xcconfig")
    }

    func testExplicitPlatformsSkipTheDetection() throws {
        let resolution = try xcodeVariants(configuration { $0.variantPlatforms = ["Mac Catalyst"] }, targetSDKs: ["Configured": []])

        XCTAssertEqual(resolution.variants.map(\.platform), [.device(.macCatalyst)])
        XCTAssertEqual(resolution.warnings, [])
    }

    func testEachConditionSetAddsAVariantOnTheFirstPlatformAndConfiguration() throws {
        let variants = try xcodeVariants(configuration {
            $0.variantPlatforms = ["iOS Simulator", "macOS"]
            $0.variantConfigurations = ["Release", "Debug"]
            $0.variantConditions = ["BETA", "FEATURE_X, LEGACY"]
        }).variants

        XCTAssertEqual(variants.count, 6)
        XCTAssertEqual(Array(variants.suffix(2)), [
            BuildVariant(platform: .simulator(.iOS), configuration: "Release", conditions: ["BETA"]),
            BuildVariant(platform: .simulator(.iOS), configuration: "Release", conditions: ["FEATURE_X", "LEGACY"]),
        ])
    }

    func testPlatformNames() {
        XCTAssertEqual(BuildVariant.Platform(name: "ios"), .device(.iOS))
        XCTAssertEqual(BuildVariant.Platform(name: "iOS Simulator"), .simulator(.iOS))
        XCTAssertEqual(BuildVariant.Platform(name: "iphonesimulator"), .simulator(.iOS))
        XCTAssertEqual(BuildVariant.Platform(name: "mac-catalyst"), .device(.macCatalyst))
        XCTAssertEqual(BuildVariant.Platform(name: "visionOS Simulator"), .simulator(.visionOS))
        XCTAssertNil(BuildVariant.Platform(name: "Android"))
        XCTAssertNil(BuildVariant.Platform(sdk: "maccatalyst"))
    }

    // MARK: - Arguments

    func testXcodebuildArgumentsOfAGenericDevice() {
        let variant = BuildVariant(platform: .device(.iOS), configuration: "Debug")

        XCTAssertEqual(variant.xcodebuildArguments, ["-destination", "generic/platform=iOS", "-configuration", "Debug"])
    }

    func testXcodebuildArgumentsOfASimulator() {
        let variant = BuildVariant(platform: .simulator(.tvOS), configuration: "Debug")

        XCTAssertEqual(variant.xcodebuildArguments, ["-destination", "generic/platform=tvOS Simulator", "-configuration", "Debug"])
    }

    func testXcodebuildArgumentsOfMacCatalyst() {
        let variant = BuildVariant(platform: .device(.macCatalyst), configuration: "Debug")

        XCTAssertEqual(variant.xcodebuildArguments, ["-destination", "platform=macOS,variant=Mac Catalyst", "-configuration", "Debug"])
    }

    func testTestabilityIsEnabledOnlyOutsideDebug() {
        let debug = BuildVariant(platform: .device(.macOS), configuration: "Debug")
        let release = BuildVariant(platform: .device(.macOS), configuration: "Release")
        let beta = BuildVariant(platform: .device(.macOS), configuration: "Beta")

        XCTAssertFalse(debug.xcodebuildArguments.contains("ENABLE_TESTABILITY=YES"))
        XCTAssertEqual(release.xcodebuildArguments.last, "ENABLE_TESTABILITY=YES")
        XCTAssertEqual(beta.xcodebuildArguments.last, "ENABLE_TESTABILITY=YES")
    }

    func testSwiftPackageReleaseIsBuiltWithTestability() {
        let debug = BuildVariant(platform: .host, configuration: "debug", conditions: ["BETA"])
        let release = BuildVariant(platform: .host, configuration: "release", conditions: ["BETA"])

        XCTAssertFalse(debug.swiftBuildArguments.contains("-enable-testing"))
        XCTAssertEqual(release.swiftBuildArguments, ["-c", "release", "-Xswiftc", "-DBETA", "-Xswiftc", "-enable-testing"])
    }

    func testConditionsAddToTheInheritedOnes() {
        let variant = BuildVariant(platform: .device(.iOS), configuration: "Debug", conditions: ["BETA", "FEATURE_X"])

        XCTAssertEqual(variant.xcodebuildArguments.last, "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) BETA FEATURE_X")
        XCTAssertEqual(variant.swiftBuildArguments, ["-c", "debug", "-Xswiftc", "-DBETA", "-Xswiftc", "-DFEATURE_X"])
    }

    // MARK: - Swift packages

    func testSwiftPackageDefaultsToTheHostInDebug() throws {
        let variants = try BuildVariantResolver(configuration: configuration()).swiftPackageVariants().variants

        XCTAssertEqual(variants, [BuildVariant(platform: .host, configuration: "debug")])
        XCTAssertEqual(variants[0].swiftBuildArguments, ["-c", "debug"])
        XCTAssertEqual(variants[0].platform.indexPlatform, .host)
    }

    func testSwiftPackageTriplesTimesConfigurations() throws {
        let variants = try BuildVariantResolver(configuration: configuration {
            $0.variantTriples = ["arm64-apple-ios17.0-simulator", "x86_64-unknown-linux-gnu"]
            $0.variantConfigurations = ["all"]
        }).swiftPackageVariants().variants

        XCTAssertEqual(variants.map(\.swiftBuildArguments), [
            ["--triple", "arm64-apple-ios17.0-simulator", "-c", "debug"],
            ["--triple", "arm64-apple-ios17.0-simulator", "-c", "release", "-Xswiftc", "-enable-testing"],
            ["--triple", "x86_64-unknown-linux-gnu", "-c", "debug"],
            ["--triple", "x86_64-unknown-linux-gnu", "-c", "release", "-Xswiftc", "-enable-testing"],
        ])
        XCTAssertEqual(variants[0].platform.indexPlatform, .iOS)
    }

    func testSwiftPackageRejectsOtherConfigurations() {
        let resolver = BuildVariantResolver(configuration: configuration { $0.variantConfigurations = ["Beta"] })

        assertUsageError(try resolver.swiftPackageVariants(), containing: "'beta'")
    }

    // MARK: - Validation

    func testBuildArgumentsChoosingAVariantAreAnError() {
        let conflicting = [
            ["-destination", "generic/platform=iOS"],
            ["-sdk", "iphonesimulator"],
            ["-configuration", "Release"],
            ["--triple", "arm64-apple-macosx"],
            ["--triple=arm64-apple-macosx"],
            ["-c", "release"],
            ["--configuration", "release"],
        ]
        for arguments in conflicting {
            let resolver = BuildVariantResolver(configuration: configuration { $0.buildArguments = arguments })
            assertUsageError(try resolver.validate(), containing: "'\(arguments[0])'")
        }
    }

    func testOtherBuildArgumentsAreAccepted() {
        let resolver = BuildVariantResolver(configuration: configuration {
            $0.buildArguments = ["-Xswiftc", "-c", "-skipPackagePluginValidation", "-C", "OTHER_FLAG=1"]
        })

        XCTAssertNoThrow(try resolver.validate())
    }

    func testGenericProjectConfigIsAnError() {
        let resolver = BuildVariantResolver(configuration: configuration { $0.genericProjectConfig = "project.json" })

        assertUsageError(try resolver.validate(), containing: "generic_project_config")
    }

    func testUnknownPlatformIsAnErrorNamingIt() {
        let resolver = BuildVariantResolver(configuration: configuration { $0.variantPlatforms = ["iOS", "Androidish"] })

        assertUsageError(try resolver.validate(), containing: "'Androidish'")
    }

    func testInvalidConditionsAreAnError() {
        let empty = BuildVariantResolver(configuration: configuration { $0.variantConditions = [" "] })
        let invalid = BuildVariantResolver(configuration: configuration { $0.variantConditions = ["BETA=1"] })

        assertUsageError(try empty.validate(), containing: "empty set")
        assertUsageError(try invalid.validate(), containing: "'BETA=1'")
    }

    func testPrebuiltIndexSettingsAreExposed() {
        let resolver = BuildVariantResolver(configuration: configuration {
            $0.indexStorePath = ["/tmp/store"]
            $0.skipBuild = true
        })

        XCTAssertEqual(resolver.prebuiltIndexSettings, ["index_store_path", "skip_build"])
    }
}

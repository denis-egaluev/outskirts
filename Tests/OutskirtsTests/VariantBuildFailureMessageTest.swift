import Shared
import XCTest

final class VariantBuildFailureMessageTest: XCTestCase {
    private let compileErrors = """
    Sources/App/Client.swift:12:20: error: 'Request' is not a member type of enum 'App.Endpoint'
       |                    `- error: 'Request' is not a member type of enum 'App.Endpoint'
    Sources/App/Client.swift:12:20: error: 'Request' is not a member type of enum 'App.Endpoint'
    Sources/App/Client.swift:30:5: error: cannot find 'debugOnly' in scope
    ** BUILD FAILED **
    """

    func testXcodeVariant_missingSDKGivesThePlatformAdvice() {
        let message = xcode(output: """
        xcodebuild: error: Unable to find a destination matching the provided destination specifier:
        \t\t{ generic:1, platform:visionOS }
        \tIneligible destinations for the "App" scheme:
        \t\t{ platform:visionOS, id:dvtdevice-DVTiOSDevicePlaceholder-xros, error:visionOS 2.0 is not installed. }
        """)

        XCTAssertTrue(message.contains("Settings > Components"), message)
        XCTAssertTrue(message.contains("variant_platforms"), message)
    }

    func testXcodeVariant_compileErrorsAreRelayedWithoutThePlatformAdvice() {
        let message = xcode(output: compileErrors)

        XCTAssertTrue(message.hasPrefix("Cannot build the variant 'macOS · Release' of scheme 'App':\n  Sources/App/Client.swift:12:20: error:"), message)
        XCTAssertTrue(message.contains("error: cannot find 'debugOnly' in scope"), message)
        XCTAssertTrue(message.contains("#if DEBUG"), message)
        let relayed = message.components(separatedBy: "#if DEBUG")[0]
        XCTAssertFalse(relayed.contains("`- error:"), message)
        XCTAssertFalse(message.contains("Settings > Components"), message)
        XCTAssertFalse(message.contains("variant_platforms"), message)
    }

    func testXcodeVariant_platformOutsideTheSchemePlatformsIsRelayedWithoutThePlatformAdvice() {
        let output = """
        xcodebuild: error: Unable to find a destination matching the provided destination specifier:
        \t\t{ generic:1, platform:macOS }
        \tIneligible destinations for the "App" scheme:
        \t\t{ platform:macOS, arch:arm64, error:macOS doesn't match App's supported platforms: iOS }
        """
        let message = xcode(output: output)

        XCTAssertTrue(message.contains("  { platform:macOS, arch:arm64, error:macOS doesn't match App's supported platforms: iOS }"), message)
        XCTAssertFalse(message.contains("Settings > Components"), message)
        XCTAssertFalse(message.contains("If its platform or SDK is not installed"), message)
    }

    func testPackageVariant_missingSwiftSDKGivesTheTripleAdvice() {
        let message = package(output: "error: No Swift SDK found for target triple 'wasm32-unknown-wasi'")

        XCTAssertTrue(message.contains("swift sdk install"), message)
        XCTAssertTrue(message.contains("variant_triples"), message)
    }

    func testPackageVariant_compileErrorsAreRelayedWithoutTheTripleAdvice() {
        let message = package(output: compileErrors)

        XCTAssertTrue(message.hasPrefix("Cannot build the variant 'x86_64-unknown-linux-gnu · release' of the package:\n  Sources/App/Client.swift:12:20: error:"), message)
        XCTAssertTrue(message.contains("error: cannot find 'debugOnly' in scope"), message)
        XCTAssertFalse(message.contains("swift sdk install"), message)
        XCTAssertFalse(message.contains("variant_triples"), message)
    }

    // MARK: - Private

    private func shellFailure(_ output: String) -> Error {
        PeripheryError.shellCommandFailed(cmd: ["build"], status: 65, output: output)
    }

    private func xcode(output: String) -> String {
        PeripheryError.variantBuildFailed(variant: "macOS · Release", scheme: "App", underlying: shellFailure(output)).description
    }

    private func package(output: String) -> String {
        PeripheryError.packageVariantBuildFailed(variant: "x86_64-unknown-linux-gnu · release", underlying: shellFailure(output)).description
    }
}

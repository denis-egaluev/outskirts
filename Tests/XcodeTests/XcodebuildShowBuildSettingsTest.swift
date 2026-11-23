import Shared
@testable import XcodeSupport
import XCTest

final class XcodebuildShowBuildSettingsTest: XCTestCase {
    func testSupportedPlatformsArePerTarget() throws {
        let output = """
        Command line invocation:
            xcodebuild -showBuildSettings -json
        [
          { "action": "build", "target": "App", "buildSettings": { "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SDKROOT": "iphoneos" } },
          { "action": "build", "target": "Widget", "buildSettings": { "SDKROOT": "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX15.0.sdk" } },
          { "action": "build", "target": "Unset", "buildSettings": {} }
        ]
        """

        XCTAssertEqual(try Xcodebuild.supportedSDKs(showBuildSettingsOutput: output), [
            "App": ["iphoneos", "iphonesimulator"],
            "Widget": ["macosx"],
            "Unset": [],
        ])
    }

    func testSDKOfAResolvedSDKRoot() throws {
        let output = """
        [{ "target": "App", "buildSettings": { "SDKROOT": "/SDKs/iPhoneOS18.0.sdk" } }]
        """

        XCTAssertEqual(try Xcodebuild.supportedSDKs(showBuildSettingsOutput: output), ["App": ["iphoneos"]])
    }

    func testUnreadableOutputIsAnError() {
        XCTAssertThrowsError(try Xcodebuild.supportedSDKs(showBuildSettingsOutput: "xcodebuild: error: no scheme"))
        XCTAssertThrowsError(try Xcodebuild.supportedSDKs(showBuildSettingsOutput: "[{ \"target\": 1 }]"))
    }
}

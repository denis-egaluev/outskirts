import Extensions
import SystemPackage
@testable import XcodeSupport
import XCTest

final class XcodeProjectSetupGuideTest: XCTestCase {
    func testMenuOptions_areRelativeAndSortedWhateverTheSetOrder() {
        let names = ["b/App.xcworkspace", "a/Z.xcworkspace", "c/App.xcworkspace", "a/App.xcworkspace", "App.xcworkspace"]
        let paths = Set(names.map { FilePath.current.appending($0) })

        XCTAssertEqual(XcodeProjectSetupGuide.menuOptions(paths), [
            "App.xcworkspace",
            "a/App.xcworkspace",
            "a/Z.xcworkspace",
            "b/App.xcworkspace",
            "c/App.xcworkspace",
        ])
    }
}

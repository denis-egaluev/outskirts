import My_Lib
import XCTest

final class GreeterTests: XCTestCase {
    func testGreeting() {
        XCTAssertEqual(Greeter().usedOnlyByTests(), "Test")
    }
}

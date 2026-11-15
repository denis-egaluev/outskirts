import Foundation
import Shared
import XCTest

final class PeripheryErrorDescriptionTest: XCTestCase {
    private struct PlainError: Error, CustomStringConvertible {
        var description: String {
            "plain failure"
        }
    }

    private struct ReadableError: LocalizedError {
        var errorDescription: String? {
            "readable failure"
        }
    }

    func testUnderlyingErrorShowsItsMessageWithoutTheTypeName() {
        XCTAssertEqual(PeripheryError.underlyingError(ReadableError()).localizedDescription, "readable failure")
        XCTAssertEqual(PeripheryError.underlyingError(PlainError()).localizedDescription, "plain failure")
    }

    func testJsonDeserializationErrorOmitsTheTypeName() {
        let message = PeripheryError.jsonDeserializationError(error: PlainError(), json: "{}").localizedDescription

        XCTAssertEqual(message, "JSON deserialization failed: plain failure\nJSON:\n{}")
    }
}

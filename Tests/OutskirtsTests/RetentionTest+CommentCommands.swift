@testable import TestShared
import XCTest

extension RetentionTest {
    func testIgnoreCommentTrailingEnumCase() {
        analyze(retainPublic: true) {
            assertReferenced(.enum("FixtureTrailingIgnoreEnum")) {
                self.assertReferenced(.enumelement("used"))
                self.assertReferenced(.enumelement("trailingIgnored"))
                self.assertNotReferenced(.enumelement("trailingControl"))
                self.assertReferenced(.enumelement("multiIgnoredA"))
                self.assertReferenced(.enumelement("multiIgnoredB"))
                self.assertNotReferenced(.enumelement("multiControl"))
            }
        }
    }
}

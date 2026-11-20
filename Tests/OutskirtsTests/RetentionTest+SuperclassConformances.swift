@testable import TestShared
import XCTest

extension RetentionTest {
    func testRetainsSuperclassMethodImplementingTwoRequirementsCalledThroughP() {
        analyze(retainPublic: true) {
            assertReferenced(.protocol("FixtureProtocolSharedSuperclassRequirementAP")) {
                self.assertReferenced(.functionMethodInstance("sharedRequirement()"))
            }
            assertReferenced(.class("FixtureClassSharedSuperclassRequirementABase")) {
                self.assertReferenced(.functionMethodInstance("sharedRequirement()"))
            }
        }
    }

    func testRetainsSuperclassMethodImplementingTwoRequirementsCalledThroughQ() {
        analyze(retainPublic: true) {
            assertReferenced(.protocol("FixtureProtocolSharedSuperclassRequirementBQ")) {
                self.assertReferenced(.functionMethodInstance("sharedRequirement()"))
            }
            assertReferenced(.class("FixtureClassSharedSuperclassRequirementBBase")) {
                self.assertReferenced(.functionMethodInstance("sharedRequirement()"))
            }
        }
    }
}

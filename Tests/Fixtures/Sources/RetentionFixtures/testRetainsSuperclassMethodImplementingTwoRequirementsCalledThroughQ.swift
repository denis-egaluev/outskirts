import Foundation

protocol FixtureProtocolSharedSuperclassRequirementBP {
    func sharedRequirement()
}

protocol FixtureProtocolSharedSuperclassRequirementBQ {
    func sharedRequirement()
}

class FixtureClassSharedSuperclassRequirementBBase {
    func sharedRequirement() {}
}

class FixtureClassSharedSuperclassRequirementB: FixtureClassSharedSuperclassRequirementBBase, FixtureProtocolSharedSuperclassRequirementBP, FixtureProtocolSharedSuperclassRequirementBQ {}

public class FixtureClassSharedSuperclassRequirementBRetainer {
    public func retain() {
        let value: any FixtureProtocolSharedSuperclassRequirementBQ = FixtureClassSharedSuperclassRequirementB()
        value.sharedRequirement()
    }
}

import Foundation

protocol FixtureProtocolSharedSuperclassRequirementAP {
    func sharedRequirement()
}

protocol FixtureProtocolSharedSuperclassRequirementAQ {
    func sharedRequirement()
}

class FixtureClassSharedSuperclassRequirementABase {
    func sharedRequirement() {}
}

class FixtureClassSharedSuperclassRequirementA: FixtureClassSharedSuperclassRequirementABase, FixtureProtocolSharedSuperclassRequirementAP, FixtureProtocolSharedSuperclassRequirementAQ {}

public class FixtureClassSharedSuperclassRequirementARetainer {
    public func retain() {
        let value: any FixtureProtocolSharedSuperclassRequirementAP = FixtureClassSharedSuperclassRequirementA()
        value.sharedRequirement()
    }
}

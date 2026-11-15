import Foundation

public struct FixtureStruct222: Equatable {
    let unused: Int

    init(unused: Int) {
        self.unused = unused
    }
}

public struct FixtureStruct223: Hashable {
    let unused: Int

    init(unused: Int) {
        self.unused = unused
    }
}

public final class FixtureClass222: Equatable {
    let unused: Int

    init(unused: Int) {
        self.unused = unused
    }

    public static func == (lhs: FixtureClass222, rhs: FixtureClass222) -> Bool {
        true
    }
}

public struct FixtureStruct222Comparable: Comparable {
    let unused: Int

    init(unused: Int) {
        self.unused = unused
    }

    public static func < (lhs: FixtureStruct222Comparable, rhs: FixtureStruct222Comparable) -> Bool {
        false
    }
}

public protocol FixtureProtocol222Refining: Equatable {}

public struct FixtureStruct222Refining: FixtureProtocol222Refining {
    let unused: Int

    init(unused: Int) {
        self.unused = unused
    }
}

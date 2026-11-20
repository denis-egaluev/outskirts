import Foundation

class SyntaxFixture46 {
    enum Value {
        case some(Int)
        case none
    }

    func switchCase(param: Int, other: Value) {
        switch other {
        case let .some(param):
            print(param)
        case .none:
            break
        }
    }

    func switchCaseWhere(param: Int, other: Int) {
        switch other {
        case let param where param > 0:
            print(param)
        default:
            break
        }
    }

    func ifCase(param: Int, other: Value) {
        if case let .some(param) = other {
            print(param)
        }
    }

    func usedInOtherCase(param: Int, other: Value) {
        switch other {
        case let .some(param):
            print(param)
        case .none:
            print(param)
        }
    }

    func usedInPattern(param: Int, other: Int) {
        switch other {
        case param:
            print(param)
        default:
            break
        }
    }

    func usedAsSubject(param: Value) {
        switch param {
        case let .some(param):
            print(param)
        case .none:
            break
        }
    }
}

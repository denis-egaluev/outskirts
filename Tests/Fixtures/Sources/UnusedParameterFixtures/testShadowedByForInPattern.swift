import Foundation

class SyntaxFixture44 {
    func shadowed(param: Int, items: [Int]) {
        for param in items {
            print(param)
        }
    }

    func shadowedInTuple(param: Int, items: [Int]) {
        for (index, param) in items.enumerated() where param > index {
            print(param)
        }
    }

    func usedInSequence(param: [Int]) {
        for param in param {
            print(param)
        }
    }

    func usedAfterLoop(param: Int, items: [Int]) {
        for param in items {
            print(param)
        }
        print(param)
    }
}

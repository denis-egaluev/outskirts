import Foundation

class SyntaxFixture45 {
    func ifLet(param: Int?, other: Int?) {
        if let param = other {
            print(param)
        }
    }

    func whileLet(param: Int?, other: [Int]) {
        var iterator = other.makeIterator()
        while let param = iterator.next() {
            print(param)
        }
    }

    func guardLet(param: Int?, other: Int?) {
        guard let param = other else { return }
        print(param)
    }

    func ifLetUsedInInitializer(param: Int?) {
        if let param = param {
            print(param)
        }
    }

    func ifLetUsedInElse(param: Int?, other: Int?) {
        if let param = other {
            print(param)
        } else {
            print(param as Any)
        }
    }

    func guardLetUsedInElse(param: Int?, other: Int?) {
        guard let param = other else {
            print(param as Any)
            return
        }
        print(param)
    }

    func guardLetUsedBefore(param: Int?, other: Int?) {
        print(param as Any)
        guard let param = other else { return }
        print(param)
    }

    func ifLetShorthand(param: Int?) {
        if let param {
            print(param)
        }
    }

    func whileLetShorthand(param: Int?) {
        while let param {
            print(param)
            break
        }
    }
}

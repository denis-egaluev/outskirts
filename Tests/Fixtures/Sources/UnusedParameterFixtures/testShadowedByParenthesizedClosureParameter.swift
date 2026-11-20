import Foundation

class SyntaxFixture43 {
    func typedParameter(param: Int) {
        perform { (param: Int) in print(param) }
    }

    func untypedParameters(param: Int) {
        performPair { (param, other) in print(param, other) }
    }

    func usedOutsideClosure(param: Int) {
        perform { (param: Int) in print(param) }
        print(param)
    }

    func perform(_ block: (Int) -> Void) {}
    func performPair(_ block: (Int, Int) -> Void) {}
}

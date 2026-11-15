import Foundation

class SyntaxFixture40 {
    func usedInLaterClosure(param: String) {
        perform { param in print(param) } other: { print(param) }
    }

    func usedAfterClosureArgument(param: String) {
        perform({ param in print(param) }, other: { print(param) })
    }

    func shadowedInEveryClosure(param: String) {
        perform { param in print(param) } other: { print("") }
    }

    func perform(_ first: (String) -> Void, other: () -> Void) {}
}

import Foundation

class SyntaxFixture41 {
    func myFunc(param: Int) {
        func inner(value: Int = param) {
            print(value)
        }
        inner()
    }

    func unusedOuter(param: Int) {
        func inner(value: Int = 0) {
            print(value)
        }
        inner()
    }
}

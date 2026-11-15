import Foundation

@propertyWrapper
struct SyntaxFixture42Wrapper {
    var wrappedValue: Int

    init(wrappedValue: Int, _ limit: Int) {
        self.wrappedValue = min(wrappedValue, limit)
    }
}

class SyntaxFixture42 {
    func myFunc(param: Int) {
        @SyntaxFixture42Wrapper(param) var value = 1
        print(value)
    }

    func unusedParam(param: Int) {
        @SyntaxFixture42Wrapper(0) var value = 1
        print(value)
    }
}

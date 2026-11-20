import Foundation

@propertyWrapper
struct SyntaxFixture48Wrapper {
    var wrappedValue: Int
    var projectedValue: Int { wrappedValue }
}

class SyntaxFixture48 {
    func projectionAfterLet(@SyntaxFixture48Wrapper param: Int) {
        let param = 0
        print(param, $param)
    }

    func storageAfterLet(@SyntaxFixture48Wrapper param: Int) {
        let param = 0
        print(param, _param)
    }

    func projectionInIfLet(@SyntaxFixture48Wrapper param: Int, other: Int?) {
        if let param = other {
            print(param, $param)
        }
    }

    func projectionInClosure(@SyntaxFixture48Wrapper param: Int) {
        perform { param in print(param, $param) }
    }

    func projectionInForIn(@SyntaxFixture48Wrapper param: Int, items: [Int]) {
        for param in items {
            print(param, $param)
        }
    }

    func shadowedWithoutProjection(@SyntaxFixture48Wrapper param: Int, other: Int?) {
        if let param = other {
            print(param)
        }
    }

    func perform(_ block: (Int) -> Void) {}
}

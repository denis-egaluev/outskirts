import Foundation

class SyntaxFixture47 {
    struct Failure: Error {}

    func catchLet(param: Error) {
        do {
            try perform()
        } catch let param {
            print(param)
        }
    }

    func catchImplicitError(error: Error) {
        do {
            try perform()
        } catch {
            print(error)
        }
    }

    func catchUsedAfter(param: Error) {
        do {
            try perform()
        } catch let param {
            print(param)
        }
        print(param)
    }

    func catchCastPattern(param: Error) {
        do {
            try perform()
        } catch let param as Failure {
            print(param)
        } catch {
            print(error)
        }
    }

    func perform() throws {}
}

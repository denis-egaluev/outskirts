import Foundation

public class FunctionValueHost {
    public init() {}

    init(calledInit: Int) {}

    public func entry() -> [Int] {
        _ = FunctionValueHost(calledInit: 1)
        let factory = FunctionValueHost.make
        let bound = method
        _ = calledOnly(factory(1) + bound(2))
        return [1].map(transform)
    }

    func transform(_ value: Int) -> Int { 0 }
    static func make(_ value: Int) -> Int { 0 }
    func method(_ value: Int) -> Int { 0 }
    func calledOnly(_ value: Int) -> Int { 0 }
}

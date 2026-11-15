#if canImport(ObjectiveC)
    import Foundation

    public class SelectorTargetHost: NSObject {
        public func action() -> Selector {
            _ = calledOnly(1)
            return #selector(handle(_:))
        }

        @objc func handle(_ sender: Any) {}
        @objc func calledOnly(_ value: Int) -> Int { 0 }
    }
#endif

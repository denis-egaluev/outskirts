import Foundation

enum FixtureTrailingIgnoreEnum {
    case used
    case trailingIgnored // outskirts:ignore
    case trailingControl
    case multiIgnoredA, multiIgnoredB // outskirts:ignore
    case multiControl
}

public class FixtureTrailingIgnoreEnumRetainer {
    public func retain() {
        _ = FixtureTrailingIgnoreEnum.used
    }
}

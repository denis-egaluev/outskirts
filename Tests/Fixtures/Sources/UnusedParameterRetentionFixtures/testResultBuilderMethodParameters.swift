import Foundation

@resultBuilder
public enum FixtureSumBuilder {
    public static func buildBlock(_ values: Int...) -> Int { 0 }
    public static func buildExpression(_ value: Int) -> Int { 0 }
    public static func helper(_ value: Int) -> Int { 0 }
}

import Foundation
@testable import SourceGraph
import SwiftSyntax
@testable import SyntaxAnalysis
import SystemPackage
import XCTest

final class CommentCommandTest: XCTestCase {
    func testParseIgnore() {
        assertParsesCommand("// periphery:ignore", expected: .ignore)
        assertParsesCommand("/// periphery:ignore", expected: .ignore)
        assertParsesCommand("/* periphery:ignore */", expected: .ignore)
        assertParsesCommand("/** periphery:ignore */", expected: .ignore)
    }

    func testParseIgnoreAll() {
        assertParsesCommand("// periphery:ignore:all", expected: .ignoreAll)
    }

    func testParseIgnoreParameters() {
        assertParsesCommand("// periphery:ignore:parameters foo", expected: .ignoreParameters(["foo"]))
        assertParsesCommand("// periphery:ignore:parameters foo,bar", expected: .ignoreParameters(["foo", "bar"]))
    }

    func testParseIgnoreParametersWithSpacesAroundCommas() {
        assertParsesCommand("// outskirts:ignore:parameters foo, bar", expected: .ignoreParameters(["foo", "bar"]))
        assertParsesCommand("// periphery:ignore:parameters foo , bar ,baz", expected: .ignoreParameters(["foo", "bar", "baz"]))
    }

    func testParseOutskirtsCommands() {
        assertParsesCommand("// outskirts:ignore", expected: .ignore)
        assertParsesCommand("/// outskirts:ignore", expected: .ignore)
        assertParsesCommand("/* outskirts:ignore */", expected: .ignore)
        assertParsesCommand("// outskirts:ignore:all", expected: .ignoreAll)
        assertParsesCommand("// outskirts:ignore:parameters foo,bar", expected: .ignoreParameters(["foo", "bar"]))
        assertParsesCommand("// outskirts:ignore - reason", expected: .ignore)
        assertDoesNotParseCommand("// some text outskirts:ignore")
    }

    func testAllowsLeadingWhitespace() {
        assertParsesCommand("//   periphery:ignore", expected: .ignore)
        assertParsesCommand("///  periphery:ignore", expected: .ignore)
        assertParsesCommand("/*   periphery:ignore */", expected: .ignore)
    }

    func testParsesCommandOnTheNextLineOfABlockComment() {
        assertParsesCommand("/*\n outskirts:ignore\n */", expected: .ignore)
        assertParsesCommand("/**\n periphery:ignore\n */", expected: .ignore)
        assertDoesNotParseCommand("/*\n text outskirts:ignore\n */")
    }

    func testIgnoresCommandsWithPrecedingText() {
        assertDoesNotParseCommand("// some text periphery:ignore")
        assertDoesNotParseCommand("/// Docs about periphery:ignore")
        assertDoesNotParseCommand("// `periphery:ignore` is used to ignore")
        assertDoesNotParseCommand("/* text periphery:ignore */")
    }

    func testTrailingCommentAfterHyphen() {
        assertParsesCommand("// periphery:ignore - this is a reason for ignoring", expected: .ignore)
        assertParsesCommand("// periphery:ignore:all - ignore entire file", expected: .ignoreAll)
        assertParsesCommand("// periphery:ignore:parameters foo - param is unused intentionally", expected: .ignoreParameters(["foo"]))
    }

    func testHyphenInsideValueIsNotATrailingComment() {
        assertParsesCommand(
            "// outskirts:override location=\"gen-file.swift:7:3\"",
            expected: .override([.location(FilePath("gen-file.swift").makeAbsolute(), 7, 3)])
        )
        assertParsesCommand("// outskirts:override kind=\"My - Kind\" - reason", expected: .override([.kind("My - Kind")]))
        assertParsesCommand("// periphery:override kind=\"My-Kind\"", expected: .override([.kind("My-Kind")]))
        assertParsesCommand("// periphery:override kind=My-Kind location=\"a.swift:1:1\"-reason", expected: .override([.location(FilePath("a.swift").makeAbsolute(), 1, 1)]))
        assertParsesCommand("// outskirts:ignore -reason", expected: .ignore)
        assertParsesCommand("// outskirts:ignore-reason", expected: .ignore)
        assertParsesCommand("// outskirts:ignore:all-reason", expected: .ignoreAll)
        assertParsesCommand("// outskirts:ignore:parameters foo,bar- reason", expected: .ignoreParameters(["foo", "bar"]))
    }

    // MARK: - Helpers

    private func assertParsesCommand(_ comment: String, expected: CommentCommand, file: StaticString = #file, line: UInt = #line) {
        let trivia = parseTrivia(comment)
        let commands = CommentCommand.parseCommands(in: trivia)
        XCTAssertEqual(commands.count, 1, "Expected exactly one command from '\(comment)'", file: file, line: line)
        if let command = commands.first {
            XCTAssertEqual(command, expected, "Command mismatch for '\(comment)'", file: file, line: line)
        }
    }

    private func assertDoesNotParseCommand(_ comment: String, file: StaticString = #file, line: UInt = #line) {
        let trivia = parseTrivia(comment)
        let commands = CommentCommand.parseCommands(in: trivia)
        XCTAssertTrue(commands.isEmpty, "Expected no commands from '\(comment)', but got: \(commands)", file: file, line: line)
    }

    private func parseTrivia(_ comment: String) -> Trivia {
        // Determine the trivia piece type based on comment prefix
        let piece: TriviaPiece = if comment.hasPrefix("///") {
            .docLineComment(comment)
        } else if comment.hasPrefix("//") {
            .lineComment(comment)
        } else if comment.hasPrefix("/**") {
            .docBlockComment(comment)
        } else if comment.hasPrefix("/*") {
            .blockComment(comment)
        } else {
            .lineComment(comment)
        }
        return Trivia(pieces: [piece])
    }
}

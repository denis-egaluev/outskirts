@testable import Fix
import XCTest

/// The diff of a key removal, built from the removed byte ranges, against the comparison of every line.
final class RemovalDiffTest: XCTestCase {
    private func catalog(_ members: [String], lineBreak: String = "\n", finalNewline: Bool = false) -> String {
        let text = "{\n  \"strings\" : {\n" + members.joined(separator: ",\n") + "\n  },\n  \"version\" : \"1.0\"\n}" + (finalNewline ? "\n" : "")
        return text.replacingOccurrences(of: "\n", with: lineBreak)
    }

    private func member(_ key: String, comment: String? = nil) -> String {
        "    \"\(key)\" : {\n      \"comment\" : \"\(comment ?? key)\"\n    }"
    }

    private func diffs(removing keys: Set<String>, from text: String) throws -> (fromRanges: String, ofEveryLine: String) {
        let bytes = Array(text.utf8)
        let removal = try XCStringsKeyRemover.removing(keys, from: bytes)
        let new = try XCTUnwrap(String(validating: removal.bytes, as: UTF8.self))
        let fromRanges = UnifiedDiff.diff(old: text, new: new, removing: removal.removedRanges, oldPath: "a/L.xcstrings", newPath: "b/L.xcstrings")
        let ofEveryLine = UnifiedDiff.diff(old: text, new: new, oldPath: "a/L.xcstrings", newPath: "b/L.xcstrings")
        return (fromRanges, ofEveryLine)
    }

    /// A member removed after another one leaves a choice between two equal closing lines, `    },`: the comparison
    /// of every line may keep either, depending on the rest of the file.
    func testRemovalsWithoutAChoiceOfEqualLinesGiveTheDiffOfEveryLine() throws {
        let members = (0 ..< 12).map { member("k\($0)") }
        let cases: [(Set<String>, String)] = [
            (["k0"], catalog(members)),
            (["k0", "k1", "k11"], catalog(members, finalNewline: true)),
            (["k0", "k10", "k11"], catalog(members, lineBreak: "\r\n")),
            (Set((0 ..< 12).map { "k\($0)" }), catalog(members)),
            (["b", "d"], "{\"strings\":{\"a\":{},\"b\":{},\"c\":{},\"d\":{}},\"version\":\"1.0\"}"),
            (["b"], "{\n  \"strings\" : {\n    \"a\" : { }, \"b\" : { },\n    \"c\" : { }\n  }\n}"),
        ]

        for (keys, text) in cases {
            let diffs = try diffs(removing: keys, from: text)
            XCTAssertFalse(diffs.fromRanges.isEmpty)
            XCTAssertEqual(diffs.fromRanges, diffs.ofEveryLine, "\(keys.sorted())")
        }
    }

    func testRemovedMemberShowsItsOwnLinesBetweenEqualClosingLines() throws {
        let text = catalog([member("a", comment: "c"), member("b", comment: "c"), member("c", comment: "c")])

        XCTAssertEqual(try diffs(removing: ["b"], from: text).fromRanges, [
            "--- a/L.xcstrings",
            "+++ b/L.xcstrings",
            "@@ -3,9 +3,6 @@",
            "     \"a\" : {",
            "       \"comment\" : \"c\"",
            "     },",
            "-    \"b\" : {",
            "-      \"comment\" : \"c\"",
            "-    },",
            "     \"c\" : {",
            "       \"comment\" : \"c\"",
            "     }",
        ].map { $0 + "\n" }.joined())
    }
}

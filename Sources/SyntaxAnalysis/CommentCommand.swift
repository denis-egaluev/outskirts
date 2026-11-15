import SourceGraph
import SwiftSyntax
import SystemPackage

extension CommentCommand {
    static func parseCommands(in trivia: Trivia?) -> [CommentCommand] {
        trivia?.compactMap { piece -> CommentCommand? in
            // Extract comment text and marker length based on trivia piece kind
            let parsed: (comment: String, markerLength: Int)? = switch piece {
            case let .lineComment(text): (text, 2) // //
            case let .docLineComment(text): (text, 3) // ///
            case let .blockComment(text): (text, 2) // /*
            case let .docBlockComment(text): (text, 3) // /**
            default: nil
            }

            guard let (comment, markerLength) = parsed,
                  let range = ["outskirts:", "periphery:"].compactMap({ comment.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }

            // Only respect commands at the start of a comment (after the marker and whitespace).
            let prefixStart = comment.index(comment.startIndex, offsetBy: markerLength)
            let prefixBeforeCommand = String(comment[prefixStart ..< range.lowerBound])
            guard prefixBeforeCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

            var rawCommand = String(comment[range.upperBound...]).replacingOccurrences(of: "*/", with: "").trimmed
            rawCommand = stripTrailingComment(rawCommand)
            return CommentCommand.parse(rawCommand)
        } ?? []
    }

    /// Removes the trailing comment that starts at the first '-' outside a quoted value or an unquoted `key=value`.
    static func stripTrailingComment(_ rawCommand: String) -> String {
        var isQuoted = false
        var isUnquotedValue = false

        for index in rawCommand.indices {
            let character = rawCommand[index]

            if character == "\"" {
                isQuoted.toggle()
                isUnquotedValue = false
            } else if isQuoted {
                continue
            } else if character == "=" {
                isUnquotedValue = true
            } else if character.isWhitespace {
                isUnquotedValue = false
            } else if character == "-", !isUnquotedValue {
                return String(rawCommand[..<index]).trimmed
            }
        }

        return rawCommand
    }

    static func parse(_ rawCommand: String) -> Self? {
        if rawCommand == "ignore" {
            return .ignore
        } else if rawCommand == "ignore:all" {
            return .ignoreAll
        } else if rawCommand.hasPrefix("ignore:parameters") {
            let params = rawCommand.dropFirst("ignore:parameters".count)
                .split(separator: ",")
                .map { String($0).trimmed }
                .filter { !$0.isEmpty }
            return .ignoreParameters(params)
        } else if rawCommand.hasPrefix("override") {
            let pattern = #/(?<key>\w+)="(?<value>[^"]*)"/#
            var params: [String: String] = [:]

            for match in rawCommand.matches(of: pattern) {
                let key = String(match.output.key)
                let value = String(match.output.value)
                params[key] = value
            }

            var overrides = [Override]()

            for (key, value) in params {
                switch key {
                case "location":
                    let parts = value.split(separator: ":")
                    guard let file = parts[safe: 0] else { break }

                    let line = Int(parts[safe: 1] ?? "1") ?? 1
                    let column = Int(parts[safe: 2] ?? "1") ?? 1
                    let filePath = FilePath(String(file)).makeAbsolute()

                    overrides.append(.location(filePath, line, column))
                case "kind":
                    overrides.append(.kind(value))
                default:
                    break
                }
            }

            return .override(overrides)
        }

        return nil
    }
}

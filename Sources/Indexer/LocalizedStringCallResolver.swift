import Foundation
import SyntaxAnalysis

@_silgen_name("swift_demangle")
private func swiftDemangle(
    _ mangledName: UnsafePointer<CChar>?,
    _ mangledNameLength: Int,
    _ outputBuffer: UnsafeMutablePointer<CChar>?,
    _ outputBufferSize: UnsafeMutablePointer<Int>?,
    _ flags: UInt32
) -> UnsafeMutablePointer<CChar>?

/// Determines which string literals passed to a call are localization keys, from the parameter types of the called
/// function. The callee is identified by the USRs the index store records at the callee name token; its parameter
/// labels and types are recovered by demangling the USR.
///
/// When the callee or the receiving parameter cannot be determined, the literal is conservatively assumed to be a key,
/// unless the index store decides: when it covers the literals of the call, a literal is a key only if the index store
/// records its conversion to a localized type, see `convertedLiteralKeys(_:calleeUsrsByPosition:)`. An Objective-C
/// callee, whose USR cannot be demangled, stays conservative.
enum LocalizedStringCallResolver {
    struct Parameter: Equatable {
        let label: String?
        let type: String

        var isVariadic: Bool {
            type.hasSuffix("...")
        }
    }

    static func usedKeys(
        for callSite: LocalizedStringCallSite,
        calleeUsrs: Set<String>,
        literalsDecidedByIndex: Bool = false
    ) -> Set<String> {
        guard !calleeUsrs.isEmpty else { return literalsDecidedByIndex ? [] : callSite.allKeys }

        var keys: Set<String> = []

        for usr in calleeUsrs {
            guard let demangled = demangle(usr: usr),
                  let parameters = parameters(fromDemangledSignature: demangled)
            else { return callSite.allKeys }

            keys.formUnion(usedKeys(
                for: callSite.arguments,
                parameters: parameters,
                stringKeyLabels: stringKeyLabels(ofDemangledSignature: demangled),
                genericKeyTypes: literalsDecidedByIndex ? [] : genericKeyTypes(ofDemangledSignature: demangled, parameters: parameters),
                literalsDecidedByIndex: literalsDecidedByIndex
            ))
        }

        return keys
    }

    /// The literals passed as the key of a `Dictionary` or the element of a `Set` (`dict["key"]`,
    /// `dict["key", default: 0]`, `dict.removeValue(forKey: "key")`, `set.contains("key")`). They are keys only when
    /// the project makes a localized type `Hashable`, which the caller decides.
    static func hashableKeyedKeys(for callSite: LocalizedStringCallSite, calleeUsrs: Set<String>) -> Set<String> {
        var keys: Set<String> = []

        for usr in calleeUsrs {
            guard let demangled = demangle(usr: usr),
                  hashableKeyedOwners.contains(where: { demangled.hasPrefix($0) }),
                  let parameters = parameters(fromDemangledSignature: demangled)
            else { continue }

            let normalized = parameters.map { parameter in
                let type = parameter.type.hasPrefix("__owned ") ? String(parameter.type.dropFirst("__owned ".count)) : parameter.type
                return Parameter(label: parameter.label, type: type)
            }
            keys.formUnion(usedKeys(for: callSite.arguments, parameters: normalized, genericKeyTypes: ["A"]))
        }

        return keys
    }

    /// `stringKeyLabels` are the labels of the plain string parameters that take the key itself, see
    /// `stringKeyLabels(ofDemangledSignature:)`. With `literalsDecidedByIndex`, an argument whose parameter is not known
    /// for certain is left to the index store rather than assumed to be a key.
    static func usedKeys(
        for arguments: [LocalizedStringCallSite.Argument],
        parameters: [Parameter],
        stringKeyLabels: Set<String?> = [],
        genericKeyTypes: Set<String> = [],
        literalsDecidedByIndex: Bool = false
    ) -> Set<String> {
        var keys: Set<String> = []
        var nextIndex = 0
        var lastMatched: Parameter?

        for (position, argument) in arguments.enumerated() {
            let parameter: Parameter?

            if argument.isTrailingClosure {
                // Swift skips a parameter with a default value when a later parameter requires the closure. Default
                // values are not part of the signature, so the closure may go to any parameter of function type before
                // the one of the next labeled argument: its literals are keys when any of them takes a localized value.
                let nextLabel = arguments.dropFirst(position + 1).first.map(\.label)
                let bound = nextLabel.flatMap { label in parameters[nextIndex...].firstIndex { $0.label == label } }
                let candidates = parameters[nextIndex ..< (bound ?? parameters.endIndex)].indices.filter {
                    parameters[$0].type.contains("->")
                }

                guard let first = candidates.first else {
                    if !literalsDecidedByIndex {
                        keys.formUnion(argument.keys)
                    }
                    continue
                }

                let isLocalized = { LocalizedStringSyntaxVisitor.isLocalizedType(parameters[$0].type) }
                if literalsDecidedByIndex ? candidates.allSatisfy(isLocalized) : candidates.contains(where: isLocalized) {
                    keys.formUnion(argument.keys)
                }

                lastMatched = parameters[first]
                nextIndex = first + 1
                continue
            } else if argument.label == nil, let lastMatched, lastMatched.isVariadic {
                parameter = lastMatched
            } else if let index = parameters[nextIndex...].firstIndex(where: { $0.label == argument.label }) {
                parameter = parameters[index]
                nextIndex = index + 1
            } else {
                parameter = nil
            }

            guard let parameter else {
                // The argument could not be matched to a parameter: the literals are keys unless the index store decides.
                if !literalsDecidedByIndex {
                    keys.formUnion(argument.keys)
                }
                continue
            }

            lastMatched = parameter

            if LocalizedStringSyntaxVisitor.isLocalizedType(parameter.type)
                || genericKeyTypes.contains(parameter.type)
                || (stringKeyLabels.contains(parameter.label) && stringKeyTypes.contains(parameter.type))
            {
                keys.formUnion(argument.keys)
            }
        }

        return keys
    }

    /// The keys of the literals the index store records as converted to a localized type: an `init(stringLiteral:)`
    /// or `init(stringInterpolation:)` reference of a localized type at the start of the literal. A literal without
    /// such a reference, e.g. when the toolchain does not record the conversion, is left to the other rules.
    static func convertedLiteralKeys(
        _ literals: [LocalizedStringLiteral],
        calleeUsrsByPosition: [LocalizedStringCalleePosition: Set<String>]
    ) -> Set<String> {
        literals.reduce(into: []) { keys, literal in
            let usrs = calleeUsrsByPosition[LocalizedStringCalleePosition(line: literal.line, column: literal.column)] ?? []
            if usrs.contains(where: isLocalizedLiteralInitializer(usr:)) {
                keys.insert(literal.key)
            }
        }
    }

    /// Whether the USR is the `init(stringLiteral:)` or `init(stringInterpolation:)` of a localized type, e.g.
    /// `Foundation.LocalizedStringResource.init(stringLiteral: Swift.String)`.
    static func isLocalizedLiteralInitializer(usr: String) -> Bool {
        guard usr.contains("13stringLiteral") || usr.contains("19stringInterpolation"),
              let demangled = demangle(usr: usr)
        else { return false }

        let characters = Array(demangled)
        guard let open = parameterListStart(in: characters),
              let first = parameters(fromDemangledSignature: demangled)?.first,
              literalInitializerLabels.contains(first.label)
        else { return false }

        let name = droppingGenericClause(String(characters[..<open])[...])
        guard name.hasSuffix(".init") else { return false }

        let owner = droppingGenericClause(name.dropLast(".init".count))
        let ownerName = owner.split(separator: ".").last.map(String.init) ?? ""
        return LocalizedStringSyntaxVisitor.localizedTypeNames.contains(ownerName)
    }

    static func demangle(usr: String) -> String? {
        guard usr.hasPrefix("s:") else { return nil }

        let mangled = "$s" + usr.dropFirst(2)
        return mangled.withCString { pointer -> String? in
            guard let result = swiftDemangle(pointer, strlen(pointer), nil, nil, 0) else { return nil }

            defer { free(result) }
            return String(cString: result)
        }
    }

    /// Parses the parameter list of a demangled function signature, e.g.
    /// `(extension in SwiftUI):SwiftUI.Button< where A == SwiftUI.Text>.init(_: SwiftUI.LocalizedStringKey, action: () -> ()) -> SwiftUI.Button<SwiftUI.Text>`.
    static func parameters(fromDemangledSignature signature: String) -> [Parameter]? {
        let characters = Array(signature)
        guard let open = parameterListStart(in: characters),
              let close = matchingClose(in: characters, from: open)
        else { return nil }

        let list = String(characters[(open + 1) ..< close])
        guard !list.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        return splitTopLevel(list).map(parseParameter)
    }

    /// The labels of the plain string parameters whose argument is the key itself: the unlabeled and `stringLiteral:`
    /// parameters of a localized type initializer, e.g. `SwiftUI.LocalizedStringKey.init(Swift.String)` called as
    /// `.init("key")`, and the `localized:` parameter of a `String` initializer.
    static func stringKeyLabels(ofDemangledSignature signature: String) -> Set<String?> {
        let characters = Array(signature)
        guard let open = parameterListStart(in: characters) else { return [] }

        let name = droppingGenericClause(String(characters[..<open])[...])
        guard name.hasSuffix(".init") else { return [] }

        let owner = droppingGenericClause(name.dropLast(".init".count))
        let ownerName = owner.split(separator: ".").last.map(String.init) ?? ""

        if LocalizedStringSyntaxVisitor.localizedTypeNames.contains(ownerName) {
            return [nil, "stringLiteral"]
        }

        return owner.hasSuffix("Swift.String") ? ["localized"] : []
    }

    /// The generic parameter types of a subscript whose argument may be a key: the index store records the
    /// unspecialized accessor, so `table["key"]` on a `Table<LocalizedStringKey>` cannot be told apart from a
    /// `Table<String>`, conservatively both are keys. `Dictionary` and `Set` are left out: their keys are `Hashable`, which
    /// none of the localized types is.
    static func genericKeyTypes(ofDemangledSignature signature: String, parameters: [Parameter]) -> Set<String> {
        let characters = Array(signature)
        guard let open = parameterListStart(in: characters) else { return [] }

        let name = String(characters[..<open])
        guard name.contains(".subscript."),
              !hashableKeyedOwners.contains(where: { name.hasPrefix($0) })
        else { return [] }

        return Set(parameters.map(\.type).filter(isGenericParameter))
    }

    // MARK: - Private

    /// `A`, `B1` or `τ_0_0`: a bare generic parameter, as printed by the demangler.
    private static func isGenericParameter(_ type: String) -> Bool {
        if type.hasPrefix("τ_") {
            return type.dropFirst(2).allSatisfy { $0.isNumber || $0 == "_" }
        }

        guard let first = type.first, first.isUppercase, first.isASCII else { return false }

        return type.dropFirst().allSatisfy(\.isNumber)
    }

    private static let stringKeyTypes: Set = ["Swift.String", "Swift.StaticString"]
    private static let literalInitializerLabels: Set<String?> = ["stringLiteral", "stringInterpolation"]
    private static let hashableKeyedOwners = ["Swift.Dictionary.", "Swift.Set."]

    /// `Name<A where A: P>` without its trailing generic clause.
    private static func droppingGenericClause(_ text: Substring) -> Substring {
        guard text.hasSuffix(">") else { return text }

        var depth = 0
        var index = text.endIndex

        while index > text.startIndex {
            index = text.index(before: index)

            if text[index] == ">", index == text.startIndex || text[text.index(before: index)] != "-" {
                depth += 1
            } else if text[index] == "<" {
                depth -= 1
                if depth == 0 {
                    return text[..<index]
                }
            }
        }

        return text
    }

    /// Parenthesized groups that qualify a name rather than list parameters: `(extension in Module)` and the
    /// private discriminator of `(name in _0123456789ABCDEF)`.
    private static func isNameQualifier(_ content: String) -> Bool {
        if content.hasPrefix("extension in ") {
            return true
        }

        let parts = content.components(separatedBy: " in _")
        guard parts.count == 2, let name = parts.first, let discriminator = parts.last else { return false }

        return !name.isEmpty && !name.contains(" ") && !discriminator.isEmpty && discriminator.allSatisfy(\.isHexDigit)
    }

    private static func parameterListStart(in characters: [Character]) -> Int? {
        var depth = 0
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if depth == 0, character == "(" {
                guard let close = matchingClose(in: characters, from: index) else { return nil }

                if isNameQualifier(String(characters[(index + 1) ..< close])) {
                    index = close + 1
                    continue
                }

                return index
            }

            depth += depthDelta(characters, at: index)
            index += 1
        }

        return nil
    }

    private static func matchingClose(in characters: [Character], from open: Int) -> Int? {
        var depth = 0

        for index in open ..< characters.count {
            if characters[index] == "(" {
                depth += 1
            } else if characters[index] == ")" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
        }

        return nil
    }

    private static func depthDelta(_ characters: [Character], at index: Int) -> Int {
        switch characters[index] {
        case "(", "[", "<":
            1
        case ")", "]":
            -1
        case ">":
            // The arrow of a function type is not a closing angle bracket.
            index > 0 && characters[index - 1] == "-" ? 0 : -1
        default:
            0
        }
    }

    private static func splitTopLevel(_ list: String) -> [String] {
        let characters = Array(list)
        var parts: [String] = []
        var current = ""
        var depth = 0

        for index in characters.indices {
            let character = characters[index]

            if depth == 0, character == "," {
                parts.append(current)
                current = ""
                continue
            }

            depth += depthDelta(characters, at: index)
            current.append(character)
        }

        parts.append(current)
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseParameter(_ text: String) -> Parameter {
        // A labeled parameter is `label: Type`; `_` denotes an unlabeled parameter. When none of the parameters of a
        // function have labels, the demangler prints only the types.
        if let separator = text.range(of: ": ") {
            let label = String(text[..<separator.lowerBound])

            if label.first.map({ $0.isLetter || $0 == "_" }) == true,
               label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
            {
                let type = String(text[separator.upperBound...])
                return Parameter(label: label == "_" ? nil : label, type: type)
            }
        }

        return Parameter(label: nil, type: text)
    }
}

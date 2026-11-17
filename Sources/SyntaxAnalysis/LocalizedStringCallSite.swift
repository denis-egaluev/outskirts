/// A call whose arguments include static string literals that may be localization keys.
///
/// Whether a literal is a key depends on the type of the parameter that receives it, which is only known once the
/// callee has been resolved from the index store.
public struct LocalizedStringCallSite: Hashable {
    public struct Argument: Hashable {
        public let label: String?
        public let keys: [String]
        /// The unlabeled trailing closure, matched to the next parameter of function type whatever its label.
        public let isTrailingClosure: Bool

        public init(label: String?, keys: [String], isTrailingClosure: Bool = false) {
            self.label = label
            self.keys = keys
            self.isTrailingClosure = isTrailingClosure
        }
    }

    /// The position of the callee name token (e.g. `Button` in `Button("key")`, `navigationTitle` in
    /// `.navigationTitle("key")`), where the index store records the reference to the called function, or of the
    /// opening bracket of a subscript call (`[` in `table["key"]`), where it records the subscript accessor.
    public let line: Int
    public let column: Int
    public let arguments: [Argument]
    /// Whether the index store records the conversions of the literals at their source position: false in code a
    /// macro may type-check in its expansion buffer, see `SyntaxProtocol.isInMacroExpansion`.
    public let hasIndexedLiterals: Bool
    /// Whether the call is in an `#if` clause, compiled only when the index store records a reference to its callee.
    public let isConditionallyCompiled: Bool

    public init(
        line: Int,
        column: Int,
        arguments: [Argument],
        hasIndexedLiterals: Bool = true,
        isConditionallyCompiled: Bool = false
    ) {
        self.line = line
        self.column = column
        self.arguments = arguments
        self.hasIndexedLiterals = hasIndexedLiterals
        self.isConditionallyCompiled = isConditionallyCompiled
    }

    public var allKeys: Set<String> {
        Set(arguments.flatMap(\.keys))
    }
}

/// A lookup whose key is built from a runtime value, e.g. `NSLocalizedString(name, comment: "")` or
/// `LocalizedStringKey("settings." + name)`, which cannot be matched to a catalogue key.
public struct LocalizedStringUnresolvedKey: Hashable {
    /// The bundle the key is looked up in.
    public enum BundleScope: Hashable {
        /// `bundle: .module`: only the catalogues of the calling module.
        case module
        /// Any other or no bundle argument: the bundle cannot be determined, every catalogue may hold the key.
        case unknown
    }

    /// The static text every possible key starts with, empty when the expression does not start with a literal.
    public let prefix: String
    public let bundleScope: BundleScope
    public let line: Int
    public let column: Int

    public init(prefix: String, bundleScope: BundleScope, line: Int, column: Int) {
        self.prefix = prefix
        self.bundleScope = bundleScope
        self.line = line
        self.column = column
    }
}

/// A string literal with the catalogue key it would stand for. It is a key only when the index store records its
/// implicit conversion to a localized type, an `init(stringLiteral:)` or `init(stringInterpolation:)` reference at the
/// start of the literal (its opening quote, or the first `#` of a raw string).
public struct LocalizedStringLiteral: Hashable {
    public let key: String
    public let line: Int
    public let column: Int

    public init(key: String, line: Int, column: Int) {
        self.key = key
        self.line = line
        self.column = column
    }
}

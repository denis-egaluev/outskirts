import SwiftSyntax

extension SyntaxProtocol {
    /// Whether the node may be type-checked in a macro expansion buffer rather than at its source position, where the
    /// index store would not record the conversions of its literals: an argument of a freestanding macro, or the code
    /// of a declaration with an attribute that may be an attached macro rewriting it (e.g. a body macro). Built-in
    /// attributes and the attached macros known to leave the code in place are not.
    var isInMacroExpansion: Bool {
        var current = parent

        while let ancestor = current {
            if ancestor.is(MacroExpansionExprSyntax.self) || ancestor.is(MacroExpansionDeclSyntax.self) {
                return true
            }

            if let declaration = ancestor.asProtocol(WithAttributesSyntax.self), declaration.is(DeclSyntax.self),
               declaration.attributes.contains(where: Self.mayBeRewritingMacro)
            {
                return true
            }

            current = ancestor.parent
        }

        return false
    }

    /// Whether the node is in an `#if` clause, which may not be compiled.
    var isInIfConfigClause: Bool {
        parent?.ancestorOrSelf { $0.as(IfConfigClauseSyntax.self) } != nil
    }

    private static func mayBeRewritingMacro(_ element: AttributeListSyntax.Element) -> Bool {
        guard case let .attribute(attribute) = element else { return true }

        let name = attribute.attributeName.trimmedDescription
        let lastComponent = name.split(separator: ".").last.map(String.init) ?? name
        return !lastComponent.hasPrefix("_") && !nonRewritingAttributeNames.contains(lastComponent)
    }
}

/// Built-in attributes, and the attached macros and other attributes known to leave the code of their declaration
/// in place.
private let nonRewritingAttributeNames: Set = [
    // Built-in attributes.
    "abi", "attached", "autoclosure", "available", "backDeployed", "concurrent", "convention", "derivative",
    "differentiable", "discardableResult", "dynamicCallable", "dynamicMemberLookup", "escaping", "exclusivity",
    "execution", "export", "extern", "freestanding", "frozen", "GKInspectable", "globalActor", "IBAction",
    "IBDesignable", "IBInspectable", "IBOutlet", "IBSegueAction", "implementation", "inlinable", "inline", "isolated",
    "lifetime", "main", "MainActor", "noDerivative", "nonexhaustive", "nonobjc", "NSApplicationMain", "NSCopying",
    "NSManaged", "objc", "objcMembers", "preconcurrency", "propertyWrapper", "requires_stored_property_inits",
    "resultBuilder", "retroactive", "safe", "section", "Sendable", "specialize", "storageRestrictions", "testable",
    "transpose", "UIApplicationMain", "unchecked", "unknown", "unsafe", "usableFromInline", "used",
    "warn_unqualified_access",
    // Attached macros and result builders known to leave the code in place.
    "Entry", "Observable", "ObservationIgnored", "ViewBuilder",
]

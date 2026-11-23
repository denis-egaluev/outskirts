/// With `every_variant`, the declarations of a module that share a USR at distinct locations, by USR: the branches of
/// `#if os(iOS) … #else … #endif`, or a type extended in one file per platform, indexed by different variants.
/// Declarations compare equal by USR, so the graph sets hold one of them, the canonical twin: the one that sorts
/// first, which `declaration(withUsr:)` returns and which is the only one reported. The others are kept here so that
/// their references are followed and a use of any of them makes them all used.
struct VariantTwins {
    private var twinsByUsr: [String: [Declaration]] = [:]

    /// Two declarations of a module sharing a USR at distinct locations, which the index only produces when it unites
    /// the stores of several build variants, each compiling a different branch of a conditional block.
    static func areTwins(_ declaration: Declaration, _ existing: Declaration) -> Bool {
        declaration !== existing &&
            declaration.location != existing.location &&
            !declaration.location.file.modules.isDisjoint(with: existing.location.file.modules)
    }

    /// Records the twin of `existing`, and returns whether it was not recorded yet.
    mutating func add(_ declaration: Declaration, of existing: Declaration, usr: String) -> Bool {
        var twins = twinsByUsr[usr] ?? [existing]
        guard !twins.contains(where: { $0 === declaration }) else { return false }

        twins.append(declaration)
        twinsByUsr[usr] = twins
        return true
    }

    mutating func remove(usrs: Set<String>) {
        usrs.forEach { twinsByUsr.removeValue(forKey: $0) }
    }

    /// The declaration and its twins, each once, the declaration first.
    func withTwins(_ declaration: Declaration) -> [Declaration] {
        var declarations = [declaration]
        for usr in declaration.usrs {
            for twin in twinsByUsr[usr, default: []] where !declarations.contains(where: { $0 === twin }) {
                declarations.append(twin)
            }
        }
        return declarations
    }

    /// Moves the children of the former canonical twin, and their own twins, to the new one.
    func moveChildren(from existing: Declaration, to declaration: Declaration) {
        for child in existing.declarations {
            for twin in withTwins(child) where twin.parent === existing {
                twin.parent = declaration
            }
        }
        declaration.declarations.formUnion(existing.declarations)
        existing.declarations.removeAll()
    }
}

public extension SourceGraph {
    /// The declaration and its variant twins, each once, the declaration first; only the declaration without
    /// `every_variant`.
    func withVariantTwins(_ declaration: Declaration) -> [Declaration] {
        guard keepsVariantTwins else { return [declaration] }

        return variantTwins.withTwins(declaration)
    }
}

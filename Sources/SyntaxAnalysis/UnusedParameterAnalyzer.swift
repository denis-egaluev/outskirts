import Foundation
import SourceGraph
import SwiftSyntax
import SystemPackage

public final class UnusedParameterAnalyzer {
    private enum UsageType {
        case used
        case unused
        case shadowed
    }

    public init() {}

    public func analyze(file: SourceFile, syntax: SourceFileSyntax, locationConverter: SourceLocationConverter, parseProtocols: Bool) -> [Function: Set<Parameter>] {
        let functions = UnusedParameterParser.parse(
            file: file,
            syntax: syntax,
            locationConverter: locationConverter,
            parseProtocols: parseProtocols
        )

        return functions.reduce(into: [Function: Set<Parameter>]()) { result, function in
            let params = analyze(function: function)

            if !params.isEmpty {
                result[function] = params
            }
        }
    }

    func analyze(function: Function) -> Set<Parameter> {
        Set(unusedParams(in: function))
    }

    // MARK: - Private

    private func unusedParams(in function: Function) -> [Parameter] {
        guard !function.attributes.contains(where: { $0.name == "IBAction" }) else { return [] }

        return function.parameters.filter { !isParam($0, usedIn: function) }
    }

    private func isParam(_ param: Parameter, usedIn function: Function) -> Bool {
        if case .wildcard = param.name {
            // Params named '_' are explicitly not intended for use, ignore them.
            return true
        }

        if param.isIsolated {
            return true
        }

        if isParam(param, usedForSpecializationIn: function) {
            return true
        }

        if isFunctionFatalErrorOnly(function) {
            return true
        }

        if isFunctionUnavailable(function) {
            return true
        }

        return isParam(param, usedIn: function.items)
    }

    private func isFunctionUnavailable(_ function: Function) -> Bool {
        function.attributes.contains { $0.isUnavailableOnAllPlatforms }
    }

    private func isFunctionFatalErrorOnly(_ function: Function) -> Bool {
        guard let codeBlockList = function.items.first as? GenericItem,
              codeBlockList.node.is(CodeBlockItemListSyntax.self),
              codeBlockList.items.count == 1,
              let funcCallExpr = codeBlockList.items.first as? GenericItem,
              funcCallExpr.node.is(FunctionCallExprSyntax.self),
              let identifier = funcCallExpr.items.first as? Identifier
        else { return false }

        return identifier.name == "fatalError"
    }

    private func isParam(_ param: Parameter, usedIn items: [Item]) -> Bool {
        for (index, item) in items.enumerated() {
            switch usage(of: param, in: item) {
            case .used:
                return true
            case .shadowed:
                // A shadowing name hides the param, but not its property wrapper projection or storage.
                return isProjection(of: param, usedIn: Array(items[(index + 1)...]))
            case .unused:
                break
            }
        }

        return false
    }

    private func isParam(_ param: Parameter, usedIn item: Item) -> Bool {
        switch usage(of: param, in: item) {
        case .used:
            true
        case .shadowed, .unused:
            false
        }
    }

    private func usage(of param: Parameter, in item: Item) -> UsageType {
        switch item {
        case let item as Variable:
            // First check if the param is used in the assignment expression.
            if isParam(param, usedIn: item.items) {
                return .used
            }

            // Next check if the variable shadows the param.
            if item.names.contains(param.name.text) {
                return .shadowed
            }

            return .unused
        case let item as Closure:
            // A closure parameter only shadows the param inside the closure, not in the items that follow it, such as
            // the next trailing closure of the same call.
            if item.params.contains(param.name.text) {
                return isProjection(of: param, usedIn: item.items) ? .used : .unused
            }

            if isParam(param, usedIn: item.items) {
                return .used
            }
        case let item as BindingScope:
            if isParam(param, usedIn: item.outerItems) {
                return .used
            }

            // The bound names only shadow the param in the inner items, not in the statements that follow.
            if item.names.contains(param.name.text) {
                return isProjection(of: param, usedIn: item.innerItems) ? .used : .unused
            }

            if isParam(param, usedIn: item.innerItems) {
                return .used
            }
        case let item as Function:
            // A nested function may use the param in the default value of one of its own parameters.
            let defaultValueItems = item.parameters.flatMap(\.items)
            if isParam(param, usedIn: defaultValueItems + item.items) {
                return .used
            }
        case let item as Identifier:
            return isIdentifier(item, referencing: param) ? .used : .unused
        case let item as GenericItem where item.node.is(LabeledExprListSyntax.self): // function call arguments
            for item in item.items where isParam(param, usedIn: item) {
                return .used
            }

            return .unused
        default:
            if isParam(param, usedIn: item.items) {
                return .used
            }
        }

        return .unused
    }

    private func isIdentifier(_ identifier: Identifier, referencing param: Parameter) -> Bool {
        let name = param.name.text

        if identifier.name == name {
            return true
        }

        // A property wrapper applied to a parameter exposes its projected value as '$name' and its storage as '_name'.
        return param.hasAttributes && (identifier.name == "$\(name)" || identifier.name == "_\(name)")
    }

    /// Whether the property wrapper projection '$name' or storage '_name' of the param is referenced in items where its
    /// name is shadowed. A shadowing name does not shadow these, nested shadowing is ignored to stay on the safe side.
    private func isProjection(of param: Parameter, usedIn items: [Item]) -> Bool {
        guard param.hasAttributes else { return false }

        let names = ["$\(param.name.text)", "_\(param.name.text)"]

        return items.contains { item in
            if let identifier = item as? Identifier {
                return names.contains(identifier.name)
            }

            let defaultValueItems = (item as? Function)?.parameters.flatMap(\.items) ?? []
            return isProjection(of: param, usedIn: defaultValueItems + item.items)
        }
    }

    private func isParam(_ param: Parameter, usedForSpecializationIn function: Function) -> Bool {
        guard let metatype = param.metatype else { return false }

        let parts = metatype.split(separator: ".").map { String($0) }

        guard let genericParam = parts.first,
              let member = parts.last,
              member == "Type" else { return false }

        return function.genericParameters.contains(genericParam)
    }
}

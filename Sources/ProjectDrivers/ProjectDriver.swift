import Foundation
import Indexer
import IndexStore
import Logger
import SystemPackage

public protocol ProjectDriver {
    func build() throws
    func plan(logger: ContextualLogger) throws -> IndexPlan
}

public extension ProjectDriver {
    func build() throws {}

    func plan(logger _: ContextualLogger) throws -> IndexPlan {
        IndexPlan(sourceFiles: [:])
    }
}

/// The index stores a plan reads: the configured ones, otherwise the one the driver derives from its build.
func resolveIndexStorePaths(configured: [FilePath], derive: () throws -> FilePath) rethrows -> Set<FilePath> {
    if !configured.isEmpty {
        return Set(configured)
    }
    return try [derive()]
}

/// The names of `exclude_targets` that are neither the name nor the module name of a target of the project. Such a
/// name still leaves out the index units of a module of that name, such as a dependency.
func unmatchedExcludedTargets(_ names: [String], targets: some Sequence<String>) -> [String] {
    let known = Set(targets)
    return names.filter { !known.contains($0) }
}

/// Warns about each name of `exclude_targets` that matches no target of the project.
func warnUnmatchedExcludedTargets(_ names: [String], targets: some Sequence<String>, logger: ContextualLogger) {
    for name in unmatchedExcludedTargets(names, targets: targets) {
        logger.warn("'exclude_targets' names '\(name)', which is neither the name nor the module name of a target of the project: only the index units of a module of that name, if any, are left out.")
    }
}

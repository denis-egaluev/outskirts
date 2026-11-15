import Foundation
import SystemPackage
import XcodeProj

/// Resolves the files that the file elements of a project stand for.
struct FileElementResolver {
    let sourceRoot: FilePath
    let projectName: String

    init(sourceRoot: FilePath, projectName: String) {
        self.sourceRoot = sourceRoot.lexicallyNormalized()
        self.projectName = projectName
    }

    /// The absolute path of the element, `nil` when it has none, such as an element relative to the build products
    /// directory. An element whose path cannot be resolved, such as one outside any group after a bad merge, is
    /// skipped with a warning instead of failing the scan.
    func path(of element: PBXFileElement, warn: (String) -> Void) -> FilePath? {
        do {
            return try element.fullPath(sourceRoot: sourceRoot.string).map { FilePath($0).lexicallyNormalized() }
        } catch {
            warnUnresolvable(element, warn: warn)
            return nil
        }
    }

    /// The paths of the files the element stands for: each variant of a variant group, else the element itself.
    func filePaths(of element: PBXFileElement, warn: (String) -> Void) -> [FilePath] {
        guard let variantGroup = element as? PBXVariantGroup else {
            return path(of: element, warn: warn).map { [$0] } ?? []
        }

        // XcodeProj resolves a variant group as its group path joined with the path of its base variant, whatever the
        // source tree of that variant: resolve each variant against the directory of the variant group instead.
        let variants = variantGroup.children
        let directory = variants.contains { $0.sourceTree == .group } ? self.directory(of: variantGroup, warn: warn) : nil

        return variants.compactMap { variant in
            guard variant.sourceTree == .group else { return path(of: variant, warn: warn) }
            guard let directory, let variantPath = variant.path else { return nil }

            return directory.appending(variantPath).lexicallyNormalized()
        }
    }

    // MARK: - Private

    /// The directory the variants relative to their group are resolved against.
    private func directory(of variantGroup: PBXVariantGroup, warn: (String) -> Void) -> FilePath? {
        let base: FilePath
        switch variantGroup.sourceTree {
        case .group?:
            guard let parent = variantGroup.parent else {
                warnUnresolvable(variantGroup, warn: warn)
                return nil
            }
            guard let parentPath = path(of: parent, warn: warn) else { return nil }

            base = parentPath
        case .sourceRoot?:
            base = sourceRoot
        case .absolute?:
            return variantGroup.path.map { FilePath($0).lexicallyNormalized() }
        default:
            return nil
        }

        return variantGroup.path.map { base.appending($0).lexicallyNormalized() } ?? base
    }

    private func warnUnresolvable(_ element: PBXFileElement, warn: (String) -> Void) {
        let label = element.path ?? element.name ?? element.uuid
        warn("Cannot resolve the path of file element '\(label)' of project '\(projectName)' (is it outside any group?), not analyzed.")
    }
}

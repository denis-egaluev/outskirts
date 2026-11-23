import Foundation
import SystemPackage
import XcodeProj

/// The targets a scheme builds, read from its `.xcscheme` file: `xcodebuild -list` only gives the names of the schemes.
public struct XcodeSchemeTargets {
    /// The targets the scheme names, which `build-for-testing` builds: the entries of its build action built for
    /// testing, and its testables.
    public let named: Set<XcodeTarget>
    /// The named targets and the targets of their project they explicitly depend on, recursively.
    public let built: Set<XcodeTarget>

    init(named: Set<XcodeTarget>) {
        self.named = named
        var built = named
        var pending = Array(named)
        while let target = pending.popLast() {
            for dependency in target.projectDependencies where built.insert(dependency).inserted {
                pending.append(dependency)
            }
        }
        self.built = built
    }

    /// The targets of the scheme of this name, read from the first `.xcscheme` file of that name in the shared data,
    /// then the user data, of the project or workspace, then of each of its projects. A scheme without a file is the
    /// one Xcode creates for the target of the same name. `nil` when the scheme names no target of the project, such as
    /// a scheme of Swift package products, or when its file cannot be read.
    public static func load(scheme: String, in project: XcodeProjectlike, warn: (String) -> Void) -> Self? {
        let xcscheme: XCScheme
        let base: FilePath
        do {
            guard let found = try schemeFile(named: scheme, in: project) else {
                let targets = project.targets.filter { $0.name == scheme }
                return targets.isEmpty ? nil : Self(named: targets)
            }

            xcscheme = try XCScheme(pathString: found.file.string)
            base = found.base
        } catch {
            warn("Cannot read the scheme '\(scheme)': \(error).")
            return nil
        }

        let entries = (xcscheme.buildAction?.buildActionEntries ?? []).filter { $0.buildFor.contains(.testing) }.map(\.buildableReference)
        let testables = (xcscheme.testAction?.testables ?? []).map(\.buildableReference)
        let targets = (entries + testables).reduce(into: Set<XcodeTarget>()) { result, reference in
            result.formUnion(Self.targets(referencedBy: reference, base: base, in: project))
        }
        return targets.isEmpty ? nil : Self(named: targets)
    }

    // MARK: - Private

    /// The scheme file of this name, and the folder its container references are relative to.
    private static func schemeFile(named scheme: String, in project: XcodeProjectlike) throws -> (file: FilePath, base: FilePath)? {
        let projects = Set(project.targets.map(\.project)).map(\.path).sorted { $0.string < $1.string }
        let containers = [project.path] + projects.filter { $0.lexicallyNormalized() != project.path.lexicallyNormalized() }
        let fileName = "\(scheme).xcscheme"

        for container in containers {
            let userData = container.appending("xcuserdata")
            let users = userData.exists ? try FileManager.default.contentsOfDirectory(atPath: userData.string) : []
            let candidates = [container.appending("xcshareddata/xcschemes")]
                + users.filter { $0.hasSuffix(".xcuserdatad") }.sorted().map { userData.appending($0).appending("xcschemes") }

            if let file = candidates.map({ $0.appending(fileName) }).first(where: \.exists) {
                return (file, container.removingLastComponent())
            }
        }
        return nil
    }

    /// The targets of the project a scheme entry refers to: a `container:` path relative to `base`, or an
    /// `absolute:` one, and the identifier of the target in that project, else its name.
    private static func targets(referencedBy reference: XCScheme.BuildableReference, base: FilePath, in project: XcodeProjectlike) -> Set<XcodeTarget> {
        let container = reference.referencedContainer
        let path: FilePath
        if container.hasPrefix("container:") {
            path = base.pushing(FilePath(String(container.dropFirst("container:".count))))
        } else if container.hasPrefix("absolute:") {
            path = FilePath(String(container.dropFirst("absolute:".count)))
        } else {
            return []
        }

        let normalized = path.lexicallyNormalized()
        return project.targets.filter { target in
            guard target.project.path.lexicallyNormalized() == normalized else { return false }

            return reference.blueprintIdentifier.map { $0 == target.identifier } ?? (target.name == reference.blueprintName)
        }
    }
}

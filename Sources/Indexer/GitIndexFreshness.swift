import Foundation
import Shared
import SystemPackage

/// The files of the git working tree that changed since the revision the index was built from
/// (`--index-built-from`). A file git knows is judged by its content, whatever its modification date; a file git does
/// not know, outside the working tree or ignored, or whose working tree copy it does not look at (skip-worktree,
/// assume-unchanged), is left to its modification date. Paths are compared in the composed form.
struct GitIndexFreshness: Sendable {
    /// The revision as given, for the messages.
    let revision: String
    /// Real paths of the files added, deleted, modified or renamed (old and new path) since the revision, untracked
    /// files included.
    let changed: Set<FilePath>
    /// Real paths of the files added since the revision, untracked files included.
    let added: Set<FilePath>
    /// Real paths of the files git judges: tracked now, except those it does not look at, or changed since the revision.
    let known: Set<FilePath>

    /// Throws a typed error when the directory is outside any git working tree or the revision names no commit:
    /// freshness is never judged by date when the caller asked for git.
    static func read(revision: String, in directory: FilePath) throws -> Self {
        do {
            return try readChanges(revision: revision, in: directory)
        } catch let error as GitError {
            throw PeripheryError.underlyingError(error)
        }
    }

    /// Whether the file changed since the revision; nil when git does not know it, so its date decides.
    func hasChanged(_ file: FilePath) -> Bool? {
        let path = Self.realPath(file)
        guard known.contains(path) else { return nil }

        return changed.contains(path)
    }

    /// The changed files the index cannot account for: Swift sources of the analyzed targets added since the revision
    /// that no unit describes, and changed files that the scan reads besides the index (see `isRead`). Only the files
    /// in `root` count.
    func unindexedChanges(indexed: Set<FilePath>, in root: FilePath, inputs: ScanInputs, isExcluded: (FilePath) -> Bool) -> Set<FilePath> {
        let root = Self.realPath(root)
        let indexed = Set(indexed.map(Self.realPath))
        let sourceFiles = inputs.sourceFiles.map { Set($0.map(Self.realPath)) }
        let resources = Set(inputs.resources.map(Self.realPath))

        return changed.filter { file in
            guard file.starts(with: root), !isExcluded(file) else { return false }

            if Self.isRead(file, inputs: inputs, resources: resources) {
                return true
            }

            guard file.extension == "swift", added.contains(file), !indexed.contains(file) else { return false }

            return sourceFiles?.contains(file) ?? true
        }
    }

    /// Whether the scan reads the file besides the index store, so that its changes alter the results: Xcode projects
    /// and workspaces and package manifests, by name; the resources the project driver lists, and the files in them;
    /// Metal sources and asset catalogs, when the scan reads them.
    static func isRead(_ file: FilePath, inputs: ScanInputs, resources: Set<FilePath>) -> Bool {
        guard let name = file.lastComponent?.string else { return false }

        if name == "Package.swift" || (name.hasPrefix("Package@swift-") && name.hasSuffix(".swift")) {
            return true
        }

        let fileExtension = file.extension?.lowercased()
        if fileExtension == "pbxproj" || fileExtension == "xcworkspacedata" {
            return true
        }

        if fileExtension == "metal" {
            return inputs.readsMetalSources
        }

        if file.components.dropLast().contains(where: { $0.extension?.lowercased() == "xcassets" }) {
            return inputs.readsAssetCatalogs
        }

        var path = file
        while !path.components.isEmpty {
            if resources.contains(path) {
                return true
            }
            path.removeLastComponent()
        }

        return false
    }

    // MARK: - Private

    private static func readChanges(revision: String, in directory: FilePath) throws -> Self {
        guard let topLevel = try Git.topLevel(of: directory) else {
            throw PeripheryError.indexBuiltFromNotInGitWorkTree(path: directory.string)
        }

        let root = FilePath(topLevel)
        let commit: String
        do {
            guard !revision.hasPrefix("-") else {
                throw GitError.failed(command: "rev-parse", status: 0, message: "a revision cannot start with '-'")
            }

            commit = try Git.run(["rev-parse", "--verify", "\(revision)^{commit}"], in: root)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let GitError.failed(_, _, message) {
            throw PeripheryError.indexBuiltFromUnknownRevision(revision: revision, repository: topLevel, message: message)
        }

        // Without renames, a renamed file is its deleted old path and its added new path.
        var (changed, added) = try changesSince(commit, in: root)

        // git does not track a file through a linked directory, so the paths it lists are real paths.
        let untracked = try Git.run(["ls-files", "--others", "--exclude-standard", "-z"], in: root)
            .split(separator: "\0")
            .map { root.appending(String($0)) }
        changed.formUnion(untracked)
        added.formUnion(untracked)

        // `ls-files -v` tags a file marked assume-unchanged with a lowercase letter, and one marked skip-worktree with
        // `S`: git does not look at its working tree copy, so that only its date can tell whether it changed.
        var tracked: Set<FilePath> = []
        for entry in try Git.run(["ls-files", "-v", "-z"], in: root).split(separator: "\0") {
            guard let tag = entry.first, entry.dropFirst().first == " " else {
                throw GitError.failed(command: "ls-files -v", status: 0, message: "unexpected entry '\(entry)'")
            }

            if !tag.isLowercase, tag != "S" {
                tracked.insert(root.appending(String(entry.dropFirst(2))))
            }
        }

        return Self(
            revision: revision,
            changed: Set(changed.map(composed)),
            added: Set(added.map(composed)),
            known: Set(changed.union(tracked).map(composed))
        )
    }

    /// The files added, deleted, modified or renamed in the working tree since the commit, and those added.
    private static func changesSince(_ commit: String, in root: FilePath) throws -> (changed: Set<FilePath>, added: Set<FilePath>) {
        var changed: Set<FilePath> = []
        var added: Set<FilePath> = []
        for (status, path) in try Git.changedFiles(since: commit, in: root) {
            changed.insert(root.appending(path))
            if status == "A" {
                added.insert(root.appending(path))
            }
        }

        return (changed, added)
    }

    /// The real path of a file, or of its directory for a file that no longer exists, in the composed form.
    private static func realPath(_ file: FilePath) -> FilePath {
        if file.exists {
            return composed(FilePath(RealPath.resolve(file.string)))
        }

        guard let name = file.lastComponent else { return composed(file) }

        return composed(FilePath(RealPath.resolve(file.removingLastComponent().string)).appending(name))
    }

    /// The path with its characters in the composed form (NFC): git lists composed paths on macOS
    /// (`core.precomposeUnicode`), while the file system may keep a name in the decomposed form.
    private static func composed(_ path: FilePath) -> FilePath {
        FilePath(path.string.precomposedStringWithCanonicalMapping)
    }
}

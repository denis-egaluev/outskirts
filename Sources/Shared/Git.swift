import Extensions
import Foundation
import SystemPackage

/// Runs git with an argument array, never through a shell, in the C locale, on the repository of the directory it is
/// given, without the optional locks that would make it write the index of the user.
public enum Git {
    /// The real path of the top level of the working tree that holds the directory, nil outside any working tree.
    /// Throws when git fails for another reason.
    public static func topLevel(of directory: FilePath) throws -> String? {
        let output: String
        do {
            output = try run(["rev-parse", "--show-toplevel"], in: directory)
        } catch let GitError.failed(_, _, message) where message.contains(notARepositoryMessage) {
            return nil
        }

        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw GitError.failed(command: "rev-parse --show-toplevel", status: 0, message: "no top level") }

        return RealPath.resolve(path)
    }

    /// The standard output of git; throws when it exits with a non-zero status, with what it printed on standard error.
    public static func run(_ arguments: [String], in directory: FilePath) throws -> String {
        try run(arguments, in: directory, store: .shared)
    }

    /// git runs in the store of the processes a signal stops, with those of the shell.
    static func run(_ arguments: [String], in directory: FilePath, store: ShellProcessStore) throws -> String {
        let result = try store.run(
            "/usr/bin/env",
            ["git", "--no-optional-locks", "-C", directory.string] + arguments,
            environment: environment(from: ProcessInfo.processInfo.environment)
        )
        let data = result.standardOutput
        let errorData = result.standardError
        let command = arguments.joined(separator: " ")
        guard result.status == 0 else {
            let message = String(bytes: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "standard error is not UTF-8"
            throw GitError.failed(command: command, status: result.status, message: message)
        }
        guard let string = String(bytes: data, encoding: .utf8) else {
            throw GitError.failed(command: command, status: 0, message: "the output is not UTF-8")
        }

        return string
    }

    /// The tracked files that differ between the commit and the working tree, without renames, as their status letter
    /// and their path from the top level `root`, optionally limited by a `--diff-filter`.
    ///
    /// `git diff` would refresh the stat data of the git index and write it, holding its lock while a git command of
    /// the user may need it. The plumbing `git diff-index` never writes the index: it lists a file whose stat data
    /// changed with a null object id; when its mode is unchanged, its content is hashed and compared with the commit.
    public static func changedFiles(since commit: String, in root: FilePath, diffFilter: String? = nil) throws -> [(status: Character, path: String)] {
        let filter = diffFilter.map { ["--diff-filter=\($0)"] } ?? []
        let entries = try run(["-c", "core.quotePath=false", "diff-index", "--no-renames", "-z"] + filter + [commit, "--"], in: root)
            .split(separator: "\0", omittingEmptySubsequences: true)
        guard entries.count.isMultiple(of: 2) else {
            throw GitError.failed(command: "diff-index", status: 0, message: "unexpected output")
        }

        var changed: [(status: Character, path: String)] = []
        var unhashed: [(path: String, commitObject: Substring)] = []
        for index in stride(from: 0, to: entries.count, by: 2) {
            // :<commit mode> <working tree mode> <commit object> <working tree object> <status>
            let fields = entries[index].dropFirst().split(separator: " ")
            let path = String(entries[index + 1])
            guard fields.count == 5, let status = fields[4].first else {
                throw GitError.failed(command: "diff-index", status: 0, message: "unexpected entry '\(entries[index])'")
            }

            let isRegularFile = fields[0] == "100644" || fields[0] == "100755"
            if status == "M", fields[0] == fields[1], isRegularFile, fields[3].allSatisfy({ $0 == "0" }) {
                unhashed.append((path, fields[2]))
            } else {
                changed.append((status, path))
            }
        }

        // Arguments in batches, below the limit of the command line.
        for batch in stride(from: 0, to: unhashed.count, by: 500).map({ unhashed[$0 ..< min($0 + 500, unhashed.count)] }) {
            let objects = try run(["hash-object", "--"] + batch.map(\.path), in: root).split(separator: "\n")
            guard objects.count == batch.count else {
                throw GitError.failed(command: "hash-object", status: 0, message: "\(objects.count) objects for \(batch.count) files")
            }

            for (file, object) in zip(batch, objects) where file.commitObject != object {
                changed.append(("M", file.path))
            }
        }

        return changed
    }

    /// The inherited environment in the C locale, without the variables that point git at another repository, index
    /// or configuration (`git rev-parse --local-env-vars`), such as those a git hook exports.
    private static func environment(from inherited: [String: String]) -> [String: String] {
        var environment = inherited.filter { !repositoryVariables.contains($0.key) }
        environment["LC_ALL"] = "C"

        return environment
    }

    // MARK: - Private

    /// What git prints, in the C locale, when no parent of the directory is a working tree.
    private static let notARepositoryMessage = "not a git repository (or any"

    private static let repositoryVariables: Set<String> = [
        "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_COMMON_DIR", "GIT_CONFIG", "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS", "GIT_DIR",
        "GIT_GRAFT_FILE", "GIT_IMPLICIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_NO_REPLACE_OBJECTS", "GIT_OBJECT_DIRECTORY", "GIT_PREFIX",
        "GIT_REPLACE_REF_BASE", "GIT_SHALLOW_FILE", "GIT_WORK_TREE",
    ]
}

public enum GitError: Error, CustomStringConvertible {
    case failed(command: String, status: Int32, message: String)

    public var description: String {
        switch self {
        case let .failed(command, status, message):
            "git \(command) failed with status \(status): \(message)"
        }
    }
}

public enum RealPath {
    public static func resolve(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }

        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// The path of the file relative to the root when the file lies inside it, compared as written first, then with
    /// both sides resolved, so that a link or `/tmp` against `/private/tmp` does not take the file out of the root.
    public static func relativePath(of file: FilePath, within root: FilePath) -> FilePath? {
        if let relative = lexicallyContained(file, in: root) {
            return relative
        }

        return lexicallyContained(FilePath(resolve(file.string)), in: FilePath(resolve(root.string)))
    }

    private static func lexicallyContained(_ file: FilePath, in root: FilePath) -> FilePath? {
        let relative = file.relativeTo(root)
        guard relative.components.first?.string != ".." else { return nil }

        return relative
    }
}

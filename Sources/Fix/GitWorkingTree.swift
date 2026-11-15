import Foundation
import Shared
import SystemPackage

/// The git working tree, as far as a fix may touch its files.
public enum WorkingTreeState: Sendable {
    /// Every file in the project root may be written (`--allow-dirty`).
    case ignored
    /// The real path of the top level of the working tree, the real paths of its files with uncommitted changes,
    /// untracked files included, and the real paths of its tracked files. A file that is not tracked, being ignored
    /// or in a submodule or a nested repository, is never written: git could not restore it.
    case repository(topLevel: String, uncommitted: Set<String>, tracked: Set<String>)
    /// The project is not in a git repository, so changes could not be reverted.
    case notARepository
}

/// Reads the uncommitted files of the git working tree that holds a directory. git is run with an argument array,
/// never through a shell.
public enum GitWorkingTree {
    /// Throws when git fails for another reason than the directory being outside any working tree.
    public static func state(at directory: FilePath) throws -> WorkingTreeState {
        do {
            return try readState(at: directory)
        } catch let error as GitError {
            throw PeripheryError.underlyingError(error)
        }
    }

    // MARK: - Private

    private static func readState(at directory: FilePath) throws -> WorkingTreeState {
        guard let root = try Git.topLevel(of: directory) else { return .notARepository }

        let status = try Git.run(["status", "--porcelain=v1", "-z", "--untracked-files=all", "--no-renames"], in: directory)
        let paths = status.split(separator: "\0").compactMap { entry -> String? in
            guard entry.count > 3 else { return nil }

            return RealPath.resolve(root + "/" + entry.dropFirst(3))
        }
        // git does not track a file through a linked directory, so the paths of the index are real paths. `-v` tags
        // each path: `S` for skip-worktree, a lowercase tag for assume-unchanged. git status hides the changes of
        // these files, so they count as uncommitted whatever their contents.
        var hidden: [String] = []
        let tracked = try Git.run(["ls-files", "-v", "-z", "--full-name"], in: FilePath(root))
            .split(separator: "\0")
            .compactMap { entry -> String? in
                guard entry.count > 2, let tag = entry.first else { return nil }

                let path = root + "/" + entry.dropFirst(2)
                if tag == "S" || tag.isLowercase {
                    hidden.append(path)
                }
                return path
            }
        return .repository(topLevel: root, uncommitted: Set(paths + hidden), tracked: Set(tracked))
    }
}

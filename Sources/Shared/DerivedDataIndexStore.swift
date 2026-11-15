import Foundation
import SystemPackage

public enum DerivedDataIndexStore {
    public static let relativeStorePaths = ["Index.noindex/DataStore", "Index/DataStore"]

    public static func resolve(derivedDataPath: FilePath) throws -> FilePath {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: derivedDataPath.string, isDirectory: &isDirectory) else {
            throw PeripheryError.derivedDataPathNotFound(derivedDataPath: derivedDataPath.string)
        }
        guard isDirectory.boolValue else {
            throw PeripheryError.derivedDataPathNotADirectory(derivedDataPath: derivedDataPath.string)
        }
        guard let store = preferredStore(in: derivedDataPath) else {
            let tried = relativeStorePaths.map { derivedDataPath.appending($0).string }
            throw PeripheryError.derivedDataIndexStoreNotFound(derivedDataPath: derivedDataPath.string, tried: tried)
        }

        return store
    }

    /// The index store of a DerivedData folder: the first one holding units, else the first one that exists, so an
    /// empty store left by an older Xcode layout never hides the one in use.
    public static func preferredStore(in derivedDataPath: FilePath) -> FilePath? {
        let existing = relativeStorePaths.map { derivedDataPath.appending($0) }.filter(directoryExists)
        return existing.first(where: hasUnits) ?? existing.first
    }

    public static func merge(indexStorePaths: [FilePath], derivedDataPaths: [FilePath]) throws -> [FilePath] {
        let resolved = try derivedDataPaths.map(resolve(derivedDataPath:))
        var seen = Set<FilePath>()
        return (indexStorePaths + resolved).filter { seen.insert($0.lexicallyNormalized()).inserted }
    }

    private static func hasUnits(_ store: FilePath) -> Bool {
        let units = store.appending("v5/units").string
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: units) else { return false }

        return !contents.isEmpty
    }

    private static func directoryExists(_ path: FilePath) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path.string, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

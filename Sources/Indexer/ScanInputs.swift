import SystemPackage

/// The files the scan depends on besides the index store, as the project driver lists them, for `index_built_from`:
/// a file changed since the revision outside these inputs does not make the results out of date.
public struct ScanInputs: Sendable {
    /// The Swift sources of the analyzed targets; nil when the project driver does not list them, in which case every
    /// Swift file added since the revision counts.
    let sourceFiles: Set<FilePath>?
    /// The Interface Builder files, property lists, String Catalogs, Core Data models and mappings the scan reads; a
    /// model is a directory, any file in it counts.
    let resources: Set<FilePath>
    /// Whether the scan reads the Metal sources under the project root.
    let readsMetalSources: Bool
    /// Whether the scan reads the asset catalogs the index holds generated symbols for.
    let readsAssetCatalogs: Bool

    public init(sourceFiles: Set<FilePath>?, resources: Set<FilePath>, readsMetalSources: Bool = false, readsAssetCatalogs: Bool = false) {
        self.sourceFiles = sourceFiles
        self.resources = resources
        self.readsMetalSources = readsMetalSources
        self.readsAssetCatalogs = readsAssetCatalogs
    }
}

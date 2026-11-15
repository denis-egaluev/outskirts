import Foundation
import Shared

public extension Xcodebuild {
    /// Records the project in the DerivedData folder of the current scan and marks it as used, then evicts the stale ones from the cache.
    /// Returns the evicted entries. Eviction is a clean-up: entries that cannot be removed are reported as a warning and
    /// never fail the scan.
    func refreshCache(project: XcodeProjectlike, schemes: [String], buildArguments: [String] = [], maxAgeDays: Int, maxSizeGB: Int = 0) throws -> [EvictedCacheEntry] {
        let current = try derivedDataPath(for: project, schemes: schemes, buildArguments: buildArguments)
        let currentURL = URL(fileURLWithPath: current.string)
        if FileManager.default.fileExists(atPath: currentURL.path) {
            try CacheManager.recordProject(project.path.lexicallyNormalized().string, in: currentURL)
            try CacheManager.touch(currentURL)
        }
        do {
            return try CacheManager.evictStale(
                cacheDirectory: URL(fileURLWithPath: resolvedCacheDirectory().string),
                maxAgeDays: maxAgeDays,
                maxSizeGB: maxSizeGB,
                keeping: currentURL
            )
        } catch {
            logger.warn("Cannot evict stale build caches: \(error.localizedDescription)")
            return []
        }
    }
}

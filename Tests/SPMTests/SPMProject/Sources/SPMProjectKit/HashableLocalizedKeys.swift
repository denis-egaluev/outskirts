#if canImport(Darwin)
    import Foundation

    extension LocalizedStringResource: @retroactive Hashable {
        public func hash(into hasher: inout Hasher) {
            hasher.combine(key)
        }
    }

    public enum HashableLocalizedKeys {
        public static func lookUp() -> [Int?] {
            var counts: [LocalizedStringResource: Int] = [:]
            var keys: Set<LocalizedStringResource> = []
            keys.insert("spm_hashable_insert_key")

            return [
                counts["spm_hashable_subscript_key"],
                counts["spm_hashable_default_key", default: 0],
                counts.removeValue(forKey: "spm_hashable_remove_key"),
                keys.contains("spm_hashable_contains_key") ? 1 : nil,
            ]
        }
    }
#endif

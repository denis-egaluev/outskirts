import Foundation
import SystemPackage

public extension String {
    /// The text of a Swift source file, with its leading UTF-8 byte order mark if any. Foundation drops the mark, yet
    /// the compiler, and so the index store, counts its three bytes in the columns of the first line: kept, it puts the
    /// positions of the syntax tree where the index store records them.
    init(swiftSourceAt path: FilePath) throws {
        let data = try Data(contentsOf: path.url)
        guard let source = String(validating: data, as: UTF8.self) else {
            throw CocoaError(.fileReadInapplicableStringEncoding, userInfo: [NSFilePathErrorKey: path.string])
        }

        self = source
    }
}

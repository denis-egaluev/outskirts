import Configuration
import Foundation
import IndexStore
import SystemPackage
@testable import TestShared
import XCTest

/// `every_variant` on a package built for real: debug, release and a set of compilation conditions, each in its own
/// scratch path with its own index store.
final class SPMEveryVariantTest: SPMSourceGraphTestCase {
    private var packageDirectory: URL?

    override func tearDownWithError() throws {
        if let packageDirectory {
            try FileManager.default.removeItem(at: packageDirectory)
        }
        try super.tearDownWithError()
    }

    private func makePackage() throws -> FilePath {
        let directory = try makeTemporaryDirectory("outskirts-every-variant")
        packageDirectory = directory
        let sources = directory.appendingPathComponent("Sources/VariantKit")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        // swift-tools-version:5.9
        import PackageDescription

        let package = Package(name: "VariantFixture", targets: [.target(name: "VariantKit")])
        """.write(to: directory.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        public func always() {}

        #if FOO
            public func onlyWithFoo() {}
        #endif

        #if DEBUG
            public func onlyInDebug() {}
        #else
            public func onlyInRelease() {}
        #endif
        """.write(to: sources.appendingPathComponent("Variants.swift"), atomically: true, encoding: .utf8)
        return FilePath(directory.path)
    }

    /// The names of the functions the index store defines.
    private func definedFunctions(in store: FilePath) throws -> Set<String> {
        let indexStore = try IndexStore(path: store.string)
        var names: Set<String> = []
        for unitName in indexStore.unitNames {
            let unit = try UnitReader(indexStore: indexStore, unitName: unitName)
            guard unit.moduleName == "VariantKit" else { continue }

            for recordName in unit.recordNames {
                try RecordReader(indexStore: indexStore, recordName: recordName).forEach(occurrence: { occurrence in
                    if occurrence.roles.contains(.definition), occurrence.symbol.name.hasPrefix("only") || occurrence.symbol.name == "always()" {
                        names.insert(occurrence.symbol.name)
                    }
                })
            }
        }
        return names
    }

    func testEveryVariant_indexesEachVariantInItsOwnStore() throws {
        let packagePath = try makePackage()
        let configuration = Configuration()
        configuration.everyVariant = true
        configuration.variantConfigurations = ["all"]
        configuration.variantConditions = ["FOO"]

        Self.build(projectPath: packagePath, configuration: configuration)

        let stores = Self.plan.indexStorePaths
        XCTAssertEqual(stores.count, 3)
        XCTAssertTrue(stores.allSatisfy { $0.string.contains("/.build/outskirts-variants/") }, "\(stores)")
        XCTAssertEqual(Set(try stores.map { try definedFunctions(in: $0) }), [
            ["always()", "onlyInDebug()"],
            ["always()", "onlyInRelease()"],
            ["always()", "onlyInDebug()", "onlyWithFoo()"],
        ])
    }
}

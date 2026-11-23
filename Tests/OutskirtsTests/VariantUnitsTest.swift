#if os(macOS)
    import Configuration
    import Foundation
    @testable import Indexer
    import Logger
    @testable import PeripheryKit
    import Shared
    @testable import SourceGraph
    import SystemPackage
    import TestShared
    import XCTest

    /// The same sources compiled for one platform with and without a condition, each into its own index store, read
    /// through `SourceFileCollector`. The units of the `VARIANT_B` store are older than the sources, as when only the
    /// other variant was rebuilt since the last edit.
    final class VariantUnitsTest: XCTestCase {
        private static let sources = [
            "main.swift": """
            #if VARIANT_B
                onlyB()
            #else
                onlyA()
            #endif
            """,
            "Lib.swift": """
            func onlyA() {}
            func onlyB() {}
            func unused() {}
            """,
        ]

        private var directory: URL!
        private var storeA: FilePath!
        private var storeB: FilePath!

        override func setUpWithError() throws {
            directory = try makeTemporaryDirectory("VariantUnitsTest")
            for (name, contents) in Self.sources {
                _ = try writeFile(contents + "\n", named: name, in: directory)
            }
            storeA = try compile(into: "storeA", conditions: [])
            storeB = try compile(into: "storeB", conditions: ["VARIANT_B"])
        }

        override func tearDownWithError() throws {
            try FileManager.default.removeItem(at: directory)
        }

        func testEveryVariant_readsTheUnitsOfEveryStoreOfThePlatform() throws {
            try backdateUnits(of: storeB)

            let (sourceFiles, results) = try scan(everyVariant: true)

            XCTAssertEqual(stores(of: "main.swift", in: sourceFiles), ["storeA-objects", "storeB-objects"])
            XCTAssertEqual(results, ["unused unused()"])
        }

        func testWithoutEveryVariant_theOutdatedStoreOfThePlatformIsLeftOut() throws {
            try backdateUnits(of: storeB)

            let (sourceFiles, results) = try scan(everyVariant: false)

            XCTAssertEqual(stores(of: "main.swift", in: sourceFiles), ["storeA-objects"])
            XCTAssertEqual(results, ["unused onlyB()", "unused unused()"])
        }

        func testEveryVariant_strictIndexNamesTheOutdatedStoreOfThePlatform() throws {
            try backdateUnits(of: storeB)

            XCTAssertThrowsError(try collect(everyVariant: true, strictIndex: true)) { error in
                guard case let .outdatedIndexData(message)? = error as? PeripheryError else {
                    return XCTFail("Unexpected error: \(error)")
                }

                XCTAssertTrue(message.contains("storeB"), message)
                XCTAssertFalse(message.contains("storeA"), message)
            }
        }

        func testEveryVariant_strictIndexPassesWithEveryStoreCurrent() throws {
            let sourceFiles = try collect(everyVariant: true, strictIndex: true)

            XCTAssertEqual(stores(of: "main.swift", in: sourceFiles), ["storeA-objects", "storeB-objects"])
            XCTAssertEqual(stores(of: "Lib.swift", in: sourceFiles), ["storeA-objects", "storeB-objects"])
        }

        // MARK: - Private

        /// The stores of the units of the file, named after the directory each one was compiled in.
        private func stores(of name: String, in sourceFiles: [SourceFile: [IndexUnit]]) -> [String] {
            let units = sourceFiles.first { $0.key.path.lastComponent?.string == name }?.value ?? []
            return units.map { FilePath($0.unit.workingDirectory).lastComponent?.string ?? "" }.sorted()
        }

        private func configuration(everyVariant: Bool, strictIndex: Bool = false) -> Configuration {
            let configuration = Configuration()
            configuration.everyVariant = everyVariant
            configuration.apply(\.$strictIndex, strictIndex)
            configuration.buildFilenameMatchers()
            return configuration
        }

        private func collect(everyVariant: Bool, strictIndex: Bool = false) throws -> [SourceFile: [IndexUnit]] {
            try SourceFileCollector(
                indexStorePaths: [storeA, storeB],
                excludedModules: [],
                scanInputs: ScanInputs(sourceFiles: nil, resources: []),
                logger: Logger(quiet: true, verbose: false, colorMode: .never).contextualized(with: "test"),
                configuration: configuration(everyVariant: everyVariant, strictIndex: strictIndex)
            ).collect().sourceFiles
        }

        private func scan(everyVariant: Bool) throws -> (sourceFiles: [SourceFile: [IndexUnit]], results: [String]) {
            let sourceFiles = try collect(everyVariant: everyVariant)
            let configuration = configuration(everyVariant: everyVariant)
            let logger = Logger(quiet: true, verbose: false, colorMode: .never)
            let swiftVersion = try SwiftVersion(shell: ShellImpl(logger: logger))
            let graph = SourceGraph(configuration: configuration, logger: logger)

            try IndexPipeline(
                plan: IndexPlan(sourceFiles: sourceFiles, indexStorePaths: [storeA, storeB]),
                graph: SourceGraphMutex(graph: graph),
                logger: logger.contextualized(with: "index"),
                configuration: configuration,
                swiftVersion: swiftVersion
            ).perform()
            try SourceGraphMutatorRunner(graph: graph, logger: logger, configuration: configuration, swiftVersion: swiftVersion).perform()

            let results = ScanResultBuilder.build(for: graph, configuration: configuration)
                .map { "\($0.annotation) \($0.declaration.name)" }
                .sorted()
            return (sourceFiles, results)
        }

        /// Dates the units of the store before the sources were written.
        private func backdateUnits(of store: FilePath) throws {
            let units = URL(fileURLWithPath: store.appending("v5/units").string)
            let date = Date().addingTimeInterval(-3600)
            for name in try FileManager.default.contentsOfDirectory(atPath: units.path) {
                try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: units.appendingPathComponent(name).path)
            }
        }

        private func compile(into name: String, conditions: [String]) throws -> FilePath {
            let store = directory.appendingPathComponent(name)
            let output = directory.appendingPathComponent("\(name)-objects")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let files = Self.sources.keys.sorted().map { directory.appendingPathComponent($0).path }
            let swiftc = Process()
            swiftc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            swiftc.currentDirectoryURL = output
            swiftc.arguments = ["swiftc", "-c", "-module-name", "Variants", "-index-store-path", store.path]
                + conditions.flatMap { ["-D", $0] } + files
            try swiftc.run()
            swiftc.waitUntilExit()
            XCTAssertEqual(swiftc.terminationStatus, 0)
            return FilePath(store.path)
        }
    }
#endif

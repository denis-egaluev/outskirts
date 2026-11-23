#if os(macOS)
    import Configuration
    import Foundation
    @testable import Indexer
    import IndexStore
    import Logger
    @testable import PeripheryKit
    import Shared
    @testable import SourceGraph
    import SystemPackage
    import TestShared
    import XCTest

    /// The same sources compiled with and without a condition, so that each store holds one branch of the conditional
    /// blocks: the declarations of both branches share their USRs at distinct locations, in one file or in two.
    final class VariantTwinsTest: XCTestCase {
        private static let sources = [
            "main.swift": """
            _ = shared(value: 1)
            sameFile(count: 2)
            """,
            "SharedA.swift": """
            #if !VARIANT_B
                func shared(value: Int) -> Int {
                    onlyA()
                    return 0
                }

                func onlyA() {}

                func orphan() {}
            #endif
            """,
            "SharedB.swift": """
            #if VARIANT_B
                func shared(value: Int) -> Int {
                    onlyB()
                    return value
                }

                func onlyB() {}

                func orphan() {}
            #endif
            """,
            "SameFile.swift": """
            #if VARIANT_B
                func sameFile(count: Int) {
                    print(count)
                    onlySameFileB()
                }

                func onlySameFileB() {}
            #else
                func sameFile(count: Int) {
                    onlySameFileA()
                }

                func onlySameFileA() {}
            #endif
            """,
        ]

        private var directory: URL!

        override func setUpWithError() throws {
            directory = try makeTemporaryDirectory("VariantTwinsTest")
            for (name, contents) in Self.sources {
                _ = try writeFile(contents + "\n", named: name, in: directory)
            }
        }

        override func tearDownWithError() throws {
            try FileManager.default.removeItem(at: directory)
        }

        func testTwinsAreKeptWithoutConflictAndShareTheirUse() throws {
            let (results, standardError) = try scan(everyVariant: true)

            XCTAssertFalse(standardError.contains("Declaration conflict"), standardError)
            XCTAssertEqual(describe(results), ["unused orphan() SharedA.swift:9"])
        }

        func testWithoutEveryVariantTheConflictIsWarnedAndTheResultsAreUnchanged() throws {
            let (results, standardError) = try scan(everyVariant: false)

            XCTAssertTrue(standardError.contains("Declaration conflict"), standardError)
            // The parameters used in one branch only are reported, and the twin reported for `orphan()` is whichever
            // was indexed first.
            let described = describe(results)
            XCTAssertEqual(described.filter { $0.hasPrefix("unused orphan() ") }.count, 1, "\(described)")
            XCTAssertEqual(described.filter { !$0.hasPrefix("unused orphan() ") }, [
                "unused count SameFile.swift:9",
                "unused value SharedA.swift:2",
            ])
        }

        // MARK: - Private

        private func describe(_ results: [ScanResult]) -> [String] {
            results.map { result in
                let location = result.declaration.location
                return "\(result.annotation) \(result.declaration.name) \(location.file.path.lastComponent?.string ?? ""):\(location.line)"
            }.sorted()
        }

        private func scan(everyVariant: Bool) throws -> (results: [ScanResult], standardError: String) {
            let storeA = try compile(into: "storeA", conditions: [])
            let storeB = try compile(into: "storeB", conditions: ["VARIANT_B"])

            let configuration = Configuration()
            configuration.everyVariant = everyVariant
            configuration.buildFilenameMatchers()
            let logger = Logger(quiet: false, verbose: false, colorMode: .never)
            let swiftVersion = try SwiftVersion(shell: ShellImpl(logger: logger))
            let plan = try IndexPlan(sourceFiles: sourceFiles(in: [storeA, storeB]), indexStorePaths: [storeA, storeB])
            let graph = SourceGraph(configuration: configuration, logger: logger)

            let standardError = try captureStandardError {
                try IndexPipeline(
                    plan: plan,
                    graph: SourceGraphMutex(graph: graph),
                    logger: logger.contextualized(with: "index"),
                    configuration: configuration,
                    swiftVersion: swiftVersion
                ).perform()
                try SourceGraphMutatorRunner(graph: graph, logger: logger, configuration: configuration, swiftVersion: swiftVersion).perform()
            }

            return (ScanResultBuilder.build(for: graph, configuration: configuration), standardError)
        }

        private func compile(into name: String, conditions: [String]) throws -> FilePath {
            let store = directory.appendingPathComponent(name)
            let output = directory.appendingPathComponent("\(name)-objects")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let files = Self.sources.keys.sorted().map { directory.appendingPathComponent($0).path }
            let swiftc = Process()
            swiftc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            swiftc.currentDirectoryURL = output
            swiftc.arguments = ["swiftc", "-c", "-module-name", "Twins", "-index-store-path", store.path]
                + conditions.flatMap { ["-D", $0] } + files
            try swiftc.run()
            swiftc.waitUntilExit()
            XCTAssertEqual(swiftc.terminationStatus, 0)
            return FilePath(store.path)
        }

        /// Every unit of the stores, by source file, without the selection of one unit per module and platform that
        /// `SourceFileCollector` makes.
        private func sourceFiles(in stores: [FilePath]) throws -> [SourceFile: [IndexUnit]] {
            var unitsByFile: [FilePath: [IndexUnit]] = [:]
            for path in stores {
                let store = try IndexStore(path: path.string)
                for unit in store.readUnits().units where !unit.isSystem && !unit.mainFile.isEmpty {
                    unitsByFile[FilePath(unit.mainFile), default: []].append(IndexUnit(store: store, unit: unit))
                }
            }
            return Dictionary(uniqueKeysWithValues: unitsByFile.map { (SourceFile(path: $0.key, modules: ["Twins"]), $0.value) })
        }

        private func captureStandardError(_ body: () throws -> Void) throws -> String {
            let pipe = Pipe()
            let original = dup(STDERR_FILENO)
            fflush(stderr)
            dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

            defer {
                dup2(original, STDERR_FILENO)
                close(original)
            }

            try body()
            fflush(stderr)
            dup2(original, STDERR_FILENO)
            pipe.fileHandleForWriting.closeFile()
            return try XCTUnwrap(String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8))
        }
    }
#endif

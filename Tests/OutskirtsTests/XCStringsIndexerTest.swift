import Configuration
import Foundation
@testable import Indexer
import Logger
import SourceGraph
import SystemPackage
import TestShared
import XCTest

final class XCStringsIndexerTest: XCTestCase {
    private let quietLogger = Logger(quiet: true, verbose: false, colorMode: .never)

    func testCatalogsOfInterfaceBuilderFilesAreNotAnalysed() throws {
        let root = FilePath(uniqueTemporaryURL("XCStringsIndexerTest").path)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: root.string) }
        try FileManager.default.createDirectory(atPath: root.string, withIntermediateDirectories: true)

        let catalogs = ["Main", "Settings", "Localizable", "Other/Detail"].map { root.appending("\($0).xcstrings") }
        try FileManager.default.createDirectory(atPath: root.appending("Other").string, withIntermediateDirectories: true)
        for (index, catalog) in catalogs.enumerated() {
            try Data(#"{"sourceLanguage":"en","version":"1.0","strings":{"key\#(index)":{}}}"#.utf8).write(to: catalog.url)
        }

        let configuration = Configuration()
        configuration.projectRoot = root
        let graph = SourceGraph(configuration: configuration, logger: quietLogger)
        try XCStringsIndexer(
            files: Set(catalogs),
            interfaceBuilderFiles: [
                root.appending("Base.lproj/Main.storyboard"),
                root.appending("Settings.xib"),
                root.appending("Elsewhere/Localizable.xib"),
                root.appending("Other/Sub/Detail.xib"),
            ],
            graph: SourceGraphMutex(graph: graph),
            logger: quietLogger.contextualized(with: "test"),
            configuration: configuration
        ).perform()

        XCTAssertEqual(graph.allDeclarations.filter { $0.kind == .localizedString }.map(\.name).sorted(), ["key2", "key3"])
    }
}

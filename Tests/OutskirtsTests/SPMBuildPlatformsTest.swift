import Indexer
@testable import ProjectDrivers
import XCTest

final class SPMBuildPlatformsTest: XCTestCase {
    func testHostBuildExpectsHostPlatform() {
        XCTAssertEqual(SPMProjectDriver.buildPlatforms(arguments: [], externalIndexStore: false), [.host])
    }

    func testExternalIndexStoreWithoutTripleExpectsAnyPlatform() {
        XCTAssertEqual(SPMProjectDriver.buildPlatforms(arguments: [], externalIndexStore: true), [])
        XCTAssertEqual(SPMProjectDriver.buildPlatforms(arguments: ["-c", "release"], externalIndexStore: true), [])
    }

    func testTripleSetsPlatformWithExternalIndexStore() {
        XCTAssertEqual(
            SPMProjectDriver.buildPlatforms(arguments: ["--triple", "arm64-apple-ios17.0-simulator"], externalIndexStore: true),
            [.iOS]
        )
    }

    func testTripleWithoutKnownSystemExpectsAnyPlatform() {
        XCTAssertEqual(SPMProjectDriver.buildPlatforms(arguments: ["--triple", "wasm32-unknown-wasi"], externalIndexStore: false), [])
        XCTAssertEqual(SPMProjectDriver.buildPlatforms(arguments: ["--triple=arm64-apple-none-macho"], externalIndexStore: false), [])
        XCTAssertNil(IndexPlatform(triple: "arm64-apple-none-macho"))
    }
}

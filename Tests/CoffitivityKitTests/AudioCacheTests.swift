import XCTest
@testable import CoffitivityKit

final class AudioCacheTests: XCTestCase {
    private var tmp: URL!
    private var cache: AudioCache!
    private let sound = Sound(name: "Creek", id: "creek")

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("coffitivity-tests-\(UUID().uuidString)", isDirectory: true)
        cache = AudioCache(cacheDirectory: tmp)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeTempFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testLocalURLMapsIdToMp3InCacheDir() {
        XCTAssertEqual(cache.localURL(for: sound), tmp.appendingPathComponent("creek.mp3"))
    }

    func testNotCachedThenCachedAfterStore() throws {
        XCTAssertFalse(cache.isCached(sound))
        try cache.store(downloadedFile: makeTempFile("audio"), for: sound)
        XCTAssertTrue(cache.isCached(sound))
    }

    func testStoreCreatesCacheDirectoryIfMissing() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path))
        let dest = try cache.store(downloadedFile: makeTempFile("audio"), for: sound)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
    }

    func testStoreReplacesExistingCachedFile() throws {
        try cache.store(downloadedFile: makeTempFile("old"), for: sound)
        let dest = try cache.store(downloadedFile: makeTempFile("new"), for: sound)
        XCTAssertEqual(try String(contentsOf: dest, encoding: .utf8), "new")
    }

    // Review Focus: a failed download must leave nothing cached.
    func testStoreFromMissingTempThrowsAndLeavesNothingCached() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try cache.store(downloadedFile: missing, for: sound))
        XCTAssertFalse(cache.isCached(sound))
    }

    func testClearRemovesAllCachedFiles() throws {
        try cache.store(downloadedFile: makeTempFile("audio"), for: sound)
        let other = Sound(name: "White Noise", id: "white-noise")
        try cache.store(downloadedFile: makeTempFile("audio"), for: other)
        XCTAssertTrue(cache.isCached(sound))
        XCTAssertTrue(cache.isCached(other))

        try cache.clear()

        XCTAssertFalse(cache.isCached(sound))
        XCTAssertFalse(cache.isCached(other))
    }

    func testClearOnMissingCacheDirectoryDoesNotThrow() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path))
        XCTAssertNoThrow(try cache.clear())
    }
}

import XCTest
@testable import CoffitivityKit

final class PlayerTests: XCTestCase {
    func testNowPlayingIsNilInitially() {
        XCTAssertNil(Player().nowPlaying)
    }

    func testNotPlayingInitially() {
        XCTAssertFalse(Player().isPlaying)
    }

    func testInitVolumeIsClamped() {
        XCTAssertEqual(Player(volume: 5.0).volume, 1.0)
        XCTAssertEqual(Player(volume: -3.0).volume, 0.0)
    }

    func testSetVolumeIsClampedToUnitRange() {
        let p = Player(volume: 0.5)
        p.setVolume(2.0)
        XCTAssertEqual(p.volume, 1.0)
        p.setVolume(-1.0)
        XCTAssertEqual(p.volume, 0.0)
        p.setVolume(0.3)
        XCTAssertEqual(p.volume, 0.3, accuracy: 0.0001)
    }

    func testPlayMissingFileReturnsFalseAndDoesNotSetNowPlaying() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mp3")
        let p = Player()
        XCTAssertFalse(p.play(localURL: missing, id: "creek"))
        XCTAssertNil(p.nowPlaying)
    }

    func testPlaySetsIsPlaying() throws {
        let url = try Self.makeSilentWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        let p = Player(volume: 0)
        XCTAssertTrue(p.play(localURL: url, id: "creek"))
        XCTAssertTrue(p.isPlaying)
        XCTAssertFalse(p.isPaused)
        XCTAssertEqual(p.nowPlaying, "creek")
    }

    func testPauseStopsPlayingButKeepsSoundLoaded() throws {
        let url = try Self.makeSilentWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        let p = Player(volume: 0)
        XCTAssertTrue(p.play(localURL: url, id: "creek"))
        p.pause()
        XCTAssertFalse(p.isPlaying)
        XCTAssertTrue(p.isPaused)
        XCTAssertEqual(p.nowPlaying, "creek")   // still loaded, ready to resume
    }

    func testResumeAfterPauseStartsPlayingAgain() throws {
        let url = try Self.makeSilentWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        let p = Player(volume: 0)
        XCTAssertTrue(p.play(localURL: url, id: "creek"))
        p.pause()
        p.resume()
        XCTAssertTrue(p.isPlaying)
        XCTAssertFalse(p.isPaused)
    }

    func testStopClearsPausedState() throws {
        let url = try Self.makeSilentWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        let p = Player(volume: 0)
        XCTAssertTrue(p.play(localURL: url, id: "creek"))
        p.pause()
        p.stop()
        XCTAssertFalse(p.isPlaying)
        XCTAssertFalse(p.isPaused)
        XCTAssertNil(p.nowPlaying)
    }

    func testPauseWithNothingLoadedIsNoOp() {
        let p = Player()
        p.pause()
        XCTAssertFalse(p.isPaused)
        XCTAssertFalse(p.isPlaying)
    }

    // A tiny valid silent PCM WAV, so a real AVAudioPlayer can load it in tests
    // without producing sound or depending on a bundled asset.
    static func makeSilentWAV() throws -> URL {
        let sampleRate: UInt32 = 8000
        let numSamples: UInt32 = 800          // 0.1s
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign = channels * bitsPerSample / 8
        let byteRate = sampleRate * UInt32(blockAlign)
        let dataSize = numSamples * UInt32(blockAlign)

        var d = Data()
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }

        d.append(Data("RIFF".utf8))
        u32(36 + dataSize)
        d.append(Data("WAVE".utf8))
        d.append(Data("fmt ".utf8))
        u32(16)                 // PCM fmt chunk size
        u16(1)                  // PCM
        u16(channels)
        u32(sampleRate)
        u32(byteRate)
        u16(blockAlign)
        u16(bitsPerSample)
        d.append(Data("data".utf8))
        u32(dataSize)
        d.append(Data(count: Int(dataSize)))   // silence

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        try d.write(to: url)
        return url
    }
}

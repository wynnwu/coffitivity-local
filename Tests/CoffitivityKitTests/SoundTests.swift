import XCTest
@testable import CoffitivityKit

final class SoundTests: XCTestCase {
    func testThereAreNineSounds() {
        XCTAssertEqual(Sound.all.count, 9)
    }

    func testAllIdsAreUnique() {
        let ids = Sound.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testUrlIsBuiltFromId() {
        let s = Sound(name: "Creek", id: "creek")
        XCTAssertEqual(s.url.absoluteString, "https://audios.coffitivity.com/creek.mp3")
    }

    func testEveryStandardSoundHasHttpsCoffitivityUrlAndNonEmptyName() {
        for s in Sound.all {
            XCTAssertFalse(s.name.isEmpty)
            XCTAssertEqual(s.url.scheme, "https")
            XCTAssertEqual(s.url.host, "audios.coffitivity.com")
            XCTAssertEqual(s.url.absoluteString, "https://audios.coffitivity.com/\(s.id).mp3")
        }
    }
}

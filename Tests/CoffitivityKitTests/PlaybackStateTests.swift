import XCTest
@testable import CoffitivityKit

final class PlaybackStateTests: XCTestCase {

    // MARK: Clicking a sound in the list

    func testClickingUncachedSoundStartsDownloadAndBecomesCurrent() {
        var s = PlaybackState()
        XCTAssertEqual(s.clickSound(id: "morning", isCached: false, isPlaying: false, isPaused: false),
                       .startDownload("morning"))
        XCTAssertEqual(s.currentId, "morning")
    }

    func testClickingCachedSoundPlaysAndBecomesCurrent() {
        var s = PlaybackState()
        XCTAssertEqual(s.clickSound(id: "white", isCached: true, isPlaying: false, isPaused: false),
                       .play("white"))
        XCTAssertEqual(s.currentId, "white")
    }

    // The hijack bug: a slow download that finishes after the user switched away must NOT start playing.
    func testCompletionIsIgnoredWhenUserSwitchedToAnotherSound() {
        var s = PlaybackState()
        XCTAssertEqual(s.clickSound(id: "morning", isCached: false, isPlaying: false, isPaused: false),
                       .startDownload("morning"))
        XCTAssertEqual(s.clickSound(id: "white", isCached: true, isPlaying: false, isPaused: false),
                       .play("white"))
        XCTAssertEqual(s.downloadFinished(id: "morning", success: true), .ignore)
    }

    func testCompletionPlaysWhenStillCurrent() {
        var s = PlaybackState()
        XCTAssertEqual(s.clickSound(id: "morning", isCached: false, isPlaying: false, isPaused: false),
                       .startDownload("morning"))
        XCTAssertEqual(s.downloadFinished(id: "morning", success: true), .play("morning"))
    }

    func testClickingSoundAlreadyDownloadingIsIgnored() {
        var s = PlaybackState()
        XCTAssertEqual(s.clickSound(id: "morning", isCached: false, isPlaying: false, isPaused: false),
                       .startDownload("morning"))
        XCTAssertEqual(s.clickSound(id: "morning", isCached: false, isPlaying: false, isPaused: false),
                       .ignore)
    }

    func testConcurrentDownloadsAreTrackedIndependently() {
        var s = PlaybackState()
        XCTAssertEqual(s.clickSound(id: "morning", isCached: false, isPlaying: false, isPaused: false),
                       .startDownload("morning"))
        XCTAssertEqual(s.clickSound(id: "lunch", isCached: false, isPlaying: false, isPaused: false),
                       .startDownload("lunch"))
        XCTAssertTrue(s.isDownloading("morning"))
        XCTAssertTrue(s.isDownloading("lunch"))
        XCTAssertEqual(s.downloadFinished(id: "morning", success: true), .ignore) // current is lunch
        XCTAssertFalse(s.isDownloading("morning"))
        XCTAssertTrue(s.isDownloading("lunch"))
    }

    func testClickingPlayingCurrentSoundPausesIt() {
        var s = PlaybackState()
        XCTAssertEqual(s.clickSound(id: "white", isCached: true, isPlaying: false, isPaused: false),
                       .play("white"))
        XCTAssertEqual(s.clickSound(id: "white", isCached: true, isPlaying: true, isPaused: false),
                       .pause)
    }

    func testClickingPausedCurrentSoundResumesIt() {
        var s = PlaybackState()
        XCTAssertEqual(s.clickSound(id: "white", isCached: true, isPlaying: false, isPaused: false),
                       .play("white"))
        XCTAssertEqual(s.clickSound(id: "white", isCached: true, isPlaying: false, isPaused: true),
                       .resume)
    }

    func testFailedDownloadErrorsOnlyWhenStillCurrent() {
        var s = PlaybackState()
        XCTAssertEqual(s.clickSound(id: "morning", isCached: false, isPlaying: false, isPaused: false),
                       .startDownload("morning"))
        XCTAssertEqual(s.downloadFinished(id: "morning", success: false), .error("morning"))

        var s2 = PlaybackState()
        XCTAssertEqual(s2.clickSound(id: "morning", isCached: false, isPlaying: false, isPaused: false),
                       .startDownload("morning"))
        XCTAssertEqual(s2.clickSound(id: "white", isCached: true, isPlaying: false, isPaused: false),
                       .play("white"))
        XCTAssertEqual(s2.downloadFinished(id: "morning", success: false), .ignore)
    }

    // MARK: The big play/pause button (acts on the current sound)

    func testPlayPauseIsIgnoredWhenNothingIsCurrent() {
        var s = PlaybackState()
        XCTAssertEqual(s.clickPlayPause(isCached: false, isPlaying: false, isPaused: false), .ignore)
    }

    func testPlayPausePausesWhenCurrentIsPlaying() {
        var s = PlaybackState(currentId: "creek")
        XCTAssertEqual(s.clickPlayPause(isCached: true, isPlaying: true, isPaused: false), .pause)
    }

    func testPlayPauseResumesWhenCurrentIsPaused() {
        var s = PlaybackState(currentId: "creek")
        XCTAssertEqual(s.clickPlayPause(isCached: true, isPlaying: false, isPaused: true), .resume)
    }

    func testPlayPausePlaysCurrentWhenStoppedAndCached() {
        var s = PlaybackState(currentId: "creek")
        XCTAssertEqual(s.clickPlayPause(isCached: true, isPlaying: false, isPaused: false), .play("creek"))
    }

    func testPlayPauseDownloadsCurrentWhenStoppedAndUncached() {
        var s = PlaybackState(currentId: "creek")
        XCTAssertEqual(s.clickPlayPause(isCached: false, isPlaying: false, isPaused: false),
                       .startDownload("creek"))
    }

    // Persisted "resume last sound": the app starts with a remembered current sound,
    // and one press of the play button plays it.
    func testPersistedCurrentSoundPlaysOnFirstPlayPause() {
        var s = PlaybackState(currentId: "blue-noise")
        XCTAssertEqual(s.currentId, "blue-noise")
        XCTAssertEqual(s.clickPlayPause(isCached: true, isPlaying: false, isPaused: false),
                       .play("blue-noise"))
    }
}

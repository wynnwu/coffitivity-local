import Foundation

/// Pure decision model for the menu. It tracks the user's current sound
/// (`currentId`, which the controller persists across launches) and every
/// in-flight download, and decides what a click or a finished download should
/// do. Keeping it free of AppKit/network makes the play/pause and download
/// concurrency logic testable.
public struct PlaybackState: Equatable {
    public enum Action: Equatable {
        case pause
        case resume
        case play(String)
        case startDownload(String)
        case ignore
    }

    public enum CompletionResult: Equatable {
        case play(String)
        case error(String)
        case ignore
    }

    /// The sound the play/pause button acts on and the one marked in the list.
    public private(set) var currentId: String?
    private var downloading: Set<String> = []

    public init(currentId: String? = nil) { self.currentId = currentId }

    public func isDownloading(_ id: String) -> Bool { downloading.contains(id) }

    /// A click on a sound in the list. `isPlaying`/`isPaused` describe that same
    /// sound's playback right now (both false when it isn't the loaded sound).
    public mutating func clickSound(id: String, isCached: Bool, isPlaying: Bool, isPaused: Bool) -> Action {
        if id == currentId {
            if isPlaying { return .pause }
            if isPaused { return .resume }
        }
        return start(id: id, isCached: isCached)
    }

    /// A click on the big play/pause button, which acts on the current sound.
    public mutating func clickPlayPause(isCached: Bool, isPlaying: Bool, isPaused: Bool) -> Action {
        guard let id = currentId else { return .ignore }
        if isPlaying { return .pause }
        if isPaused { return .resume }
        return start(id: id, isCached: isCached)
    }

    /// Begin playback of `id` from a stopped state, or decline to start a
    /// duplicate download of one already in flight.
    private mutating func start(id: String, isCached: Bool) -> Action {
        if downloading.contains(id) { return .ignore }
        currentId = id
        if isCached { return .play(id) }
        downloading.insert(id)
        return .startDownload(id)
    }

    /// A finished download only acts if the user still wants that sound;
    /// otherwise it is dropped (no playback hijack).
    public mutating func downloadFinished(id: String, success: Bool) -> CompletionResult {
        downloading.remove(id)
        guard currentId == id else { return .ignore }
        return success ? .play(id) : .error(id)
    }
}

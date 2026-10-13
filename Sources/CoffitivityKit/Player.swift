import Foundation
import AVFoundation

public final class Player {
    private var player: AVAudioPlayer?
    public private(set) var nowPlaying: String?
    public private(set) var isPaused: Bool = false
    public private(set) var volume: Float

    /// True when a sound is loaded and actively playing (not paused, not stopped).
    public var isPlaying: Bool { nowPlaying != nil && !isPaused }

    public init(volume: Float = 0.7) {
        self.volume = Player.clamp(volume)
    }

    static func clamp(_ v: Float) -> Float { min(max(v, 0), 1) }

    /// Play a local file on infinite loop, replacing any current playback.
    /// Returns false if the file could not be opened.
    @discardableResult
    public func play(localURL: URL, id: String) -> Bool {
        do {
            let p = try AVAudioPlayer(contentsOf: localURL)
            p.numberOfLoops = -1
            p.volume = volume
            p.prepareToPlay()
            p.play()
            player = p
            nowPlaying = id
            isPaused = false
            return true
        } catch {
            return false
        }
    }

    /// Pause the current sound, keeping its position so `resume()` continues seamlessly.
    public func pause() {
        guard player != nil, !isPaused else { return }
        player?.pause()
        isPaused = true
    }

    /// Resume a paused sound from where it left off.
    public func resume() {
        guard let p = player, isPaused else { return }
        p.play()
        isPaused = false
    }

    public func stop() {
        player?.stop()
        player = nil
        nowPlaying = nil
        isPaused = false
    }

    public func setVolume(_ v: Float) {
        volume = Player.clamp(v)
        player?.volume = volume
    }
}

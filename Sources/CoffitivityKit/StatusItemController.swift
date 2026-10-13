import AppKit

public final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let player: Player
    private let cache: AudioCache

    private var state: PlaybackState
    private var soundItems: [String: NSMenuItem] = [:]
    private var playPauseButton: NSButton?
    private let defaults: UserDefaults
    private static let volumeKey = "volume"
    private static let currentSoundKey = "currentSound"

    public init(cache: AudioCache = AudioCache(), defaults: UserDefaults = .standard) {
        self.cache = cache
        self.defaults = defaults

        let savedVolume = defaults.object(forKey: Self.volumeKey) as? Float ?? 0.7
        self.player = Player(volume: savedVolume)

        // Resume last sound: start with the remembered sound (first launch → first sound).
        let savedCurrent = defaults.string(forKey: Self.currentSoundKey)
        let validCurrent = savedCurrent.flatMap { id in
            Sound.all.contains { $0.id == id } ? id : nil
        }
        self.state = PlaybackState(currentId: validCurrent ?? Sound.all.first?.id)

        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.menu = buildMenu()
        refreshStates()
    }

    // MARK: Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(makeControlRow())
        menu.addItem(.separator())
        for sound in Sound.all {
            let item = NSMenuItem(title: sound.name,
                                  action: #selector(soundClicked(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = sound.id
            soundItems[sound.id] = item
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let more = NSMenuItem(title: "More sounds at coffitivity.com ↗",
                              action: #selector(openCoffitivity),
                              keyEquivalent: "")
        more.target = self
        menu.addItem(more)
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Cache", action: #selector(clearCacheClicked), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    /// Top row: a large play/pause button on the left, the volume slider filling the rest.
    private func makeControlRow() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 244, height: 40))

        let button = NSButton(frame: NSRect(x: 12, y: 5, width: 30, height: 30))
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryChange)
        button.image = symbolImage("play.fill", pointSize: 18, "Play")
        button.target = self
        button.action = #selector(playPauseClicked)
        container.addSubview(button)
        playPauseButton = button

        let slider = NSSlider(value: Double(player.volume), minValue: 0, maxValue: 1,
                              target: self, action: #selector(volumeChanged(_:)))
        slider.frame = NSRect(x: 54, y: 10, width: 176, height: 20)
        container.addSubview(slider)

        let item = NSMenuItem()
        item.view = container
        return item
    }

    // MARK: Actions

    @objc private func soundClicked(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        let action = state.clickSound(id: id,
                                      isCached: isCached(id),
                                      isPlaying: isPlaying(id),
                                      isPaused: isPaused(id))
        perform(action)
    }

    @objc private func playPauseClicked() {
        guard let id = state.currentId else { return }
        let action = state.clickPlayPause(isCached: isCached(id),
                                          isPlaying: isPlaying(id),
                                          isPaused: isPaused(id))
        perform(action)
    }

    private func perform(_ action: PlaybackState.Action) {
        switch action {
        case .pause:
            player.pause()
        case .resume:
            player.resume()
        case .play(let id):
            playCached(id)
        case .startDownload(let id):
            if let sound = sound(for: id) { startDownload(sound) }
        case .ignore:
            break
        }
        persistCurrent()
        refreshStates()
    }

    private func playCached(_ id: String) {
        guard let sound = sound(for: id) else { return }
        player.play(localURL: cache.localURL(for: sound), id: id)
    }

    private func startDownload(_ sound: Sound) {
        refreshStates()   // show "downloading…"
        cache.download(sound) { [weak self] result in
            guard let self = self else { return }
            let success: Bool = { if case .success = result { return true } else { return false } }()
            switch self.state.downloadFinished(id: sound.id, success: success) {
            case .play:
                self.playCached(sound.id)
            case .error:
                self.showDownloadError(sound)
            case .ignore:
                break
            }
            self.refreshStates()
        }
    }

    @objc private func volumeChanged(_ slider: NSSlider) {
        let v = Float(slider.doubleValue)
        player.setVolume(v)
        defaults.set(v, forKey: Self.volumeKey)
    }

    @objc private func openCoffitivity() {
        if let url = URL(string: "https://coffitivity.com/") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func clearCacheClicked() {
        player.stop()
        try? cache.clear()
        refreshStates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: State → UI

    private func refreshStates() {
        for sound in Sound.all {
            guard let item = soundItems[sound.id] else { continue }
            if state.isDownloading(sound.id) {
                item.title = "\(sound.name)  (downloading…)"
                item.state = .off
                item.isEnabled = false
            } else {
                item.title = sound.name
                item.state = (state.currentId == sound.id) ? .on : .off
                item.isEnabled = true
            }
        }
        playPauseButton?.image = player.isPlaying
            ? symbolImage("pause.fill", pointSize: 18, "Pause")
            : symbolImage("play.fill", pointSize: 18, "Play")
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        let name = player.isPlaying ? "cup.and.saucer.fill" : "cup.and.saucer"
        statusItem.button?.image = NSImage(systemSymbolName: name,
                                           accessibilityDescription: "Coffitivity")
    }

    private func showDownloadError(_ sound: Sound) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t download “\(sound.name)”"
        alert.informativeText = "Check your internet connection and try again."
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: Helpers

    private func persistCurrent() {
        if let id = state.currentId {
            defaults.set(id, forKey: Self.currentSoundKey)
        }
    }

    private func isCached(_ id: String) -> Bool {
        guard let sound = sound(for: id) else { return false }
        return cache.isCached(sound)
    }

    private func isPlaying(_ id: String) -> Bool {
        player.isPlaying && player.nowPlaying == id
    }

    private func isPaused(_ id: String) -> Bool {
        player.isPaused && player.nowPlaying == id
    }

    private func sound(for id: String) -> Sound? {
        Sound.all.first { $0.id == id }
    }

    private func symbolImage(_ name: String, pointSize: CGFloat, _ desc: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: desc)
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        return image?.withSymbolConfiguration(config)
    }
}

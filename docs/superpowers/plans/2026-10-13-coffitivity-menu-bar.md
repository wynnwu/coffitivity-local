# CoffitivityLocal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A tiny native macOS menu-bar app that loops any of Coffitivity's 9 free ambience tracks, caching each on first play so it works offline afterward, with a persisted volume slider.

**Architecture:** A Swift Package with a `CoffitivityKit` library (testable logic + the AppKit menu controller), a thin `CoffitivityLocal` executable (bootstrap), and a test target. Playback is `AVAudioPlayer` looping a locally-cached mp3; the UI is an `NSStatusItem` menu with no Dock icon. A `make-app.sh` bundles the release binary into a `.app`.

**Tech Stack:** Swift 5.9+ toolchain (Swift 5 language mode), AppKit, AVFoundation, Foundation `URLSession`, XCTest. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-10-13-coffitivity-menu-bar-design.md`

## Global Constraints

- Platform: macOS 13+ (`platforms: [.macOS(.v13)]`, `LSMinimumSystemVersion` `13.0`).
- No third-party dependencies anywhere in `Package.swift`.
- Audio source host (verbatim): `https://audios.coffitivity.com/<id>.mp3`. All URLs HTTPS (no ATS exception needed).
- Exactly 9 free sounds, in spec order; a sound's `id` is its mp3 file stem **and** its cache filename.
- Cache directory: `~/Library/Application Support/CoffitivityLocal/`.
- App is menu-bar only: `LSUIElement = true` and `NSApplication` activation policy `.accessory` (no Dock icon, no window).
- Menu-bar icon: SF Symbol `cup.and.saucer.fill` (no image assets shipped).
- `UserDefaults` key for volume: `volume` (Float, default `0.7`).
- Commit after every task.

## Review Focus

- **First-ever play with no network** → a clear error, no crash, nothing left in the cache. Test pinned to Task 2 (`store` from a missing temp source throws and leaves `isCached` false); offline UI behavior in Task 4 manual smoke.
- **Remote file missing / non-2xx (e.g. a renamed id → 404)** → graceful failure, never a cached HTML error page. `download` maps non-2xx to `.badStatus`; verified in Task 2 code + Task 4 manual smoke (temporarily point at a bogus id).
- **Switching sounds while one is playing** → the old one stops, only the new one plays. Single `AVAudioPlayer` replacement pinned to Task 3; manual smoke in Task 4.
- **Clicking a sound that is still downloading** → no duplicate download or double playback. Item is disabled while downloading; Task 4 manual smoke.
- **Relaunch after changing volume** → the saved volume is restored. Pinned to Task 5 (`UserDefaults` read/write) + relaunch manual smoke.

---

### Task 1: Swift package scaffolding + `Sound` model

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/CoffitivityKit/Sound.swift`
- Test: `Tests/CoffitivityKitTests/SoundTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `struct Sound { let name: String; let id: String; var url: URL }` with `init(name:id:)` and `static let all: [Sound]` (9 items). `url == https://audios.coffitivity.com/<id>.mp3`.

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CoffitivityLocal",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CoffitivityKit"),
        .executableTarget(
            name: "CoffitivityLocal",
            dependencies: ["CoffitivityKit"]
        ),
        .testTarget(
            name: "CoffitivityKitTests",
            dependencies: ["CoffitivityKit"]
        ),
    ]
)
```

- [ ] **Step 2: Create `.gitignore`**

```
.build/
*.app
.DS_Store
```

- [ ] **Step 3: Write the failing test** — `Tests/CoffitivityKitTests/SoundTests.swift`

```swift
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
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `swift test --filter SoundTests`
Expected: FAIL — `cannot find 'Sound' in scope` (type not defined yet).

- [ ] **Step 5: Implement `Sound`** — `Sources/CoffitivityKit/Sound.swift`

```swift
import Foundation

public struct Sound: Equatable, Sendable {
    public let name: String
    public let id: String   // mp3 file stem; also the cache filename

    public init(name: String, id: String) {
        self.name = name
        self.id = id
    }

    public var url: URL {
        URL(string: "https://audios.coffitivity.com/\(id).mp3")!
    }

    public static let all: [Sound] = [
        Sound(name: "Morning Murmur",        id: "morning-murmur"),
        Sound(name: "Lunchtime Lounge",      id: "lunchtime-lounge"),
        Sound(name: "University Undertones", id: "university-undertones"),
        Sound(name: "Sunny Day Café",        id: "tuesday-at-tarihi"),
        Sound(name: "Bird Songs",            id: "bird-songs"),
        Sound(name: "Heavy Wind",            id: "heavy-wind"),
        Sound(name: "Creek",                 id: "creek"),
        Sound(name: "Blue Noise",            id: "blue-noise"),
        Sound(name: "White Noise",           id: "white-noise"),
    ]
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `swift test --filter SoundTests`
Expected: PASS (4 tests).

- [ ] **Step 7: Commit**

```bash
git add Package.swift .gitignore Sources/CoffitivityKit/Sound.swift Tests/CoffitivityKitTests/SoundTests.swift
git commit -m "feat: add Swift package and Sound model with the 9 free tracks"
```

---

### Task 2: `AudioCache` — disk cache + atomic store + download

**Files:**
- Create: `Sources/CoffitivityKit/AudioCache.swift`
- Test: `Tests/CoffitivityKitTests/AudioCacheTests.swift`

**Interfaces:**
- Consumes: `Sound` (Task 1).
- Produces:
  - `final class AudioCache` with `init(cacheDirectory: URL, fileManager: FileManager = .default)` and `convenience init()` (defaults to `~/Library/Application Support/CoffitivityLocal/`).
  - `var cacheDirectory: URL`
  - `func localURL(for sound: Sound) -> URL`
  - `func isCached(_ sound: Sound) -> Bool`
  - `@discardableResult func store(downloadedFile tempURL: URL, for sound: Sound) throws -> URL`
  - `func download(_ sound: Sound, session: URLSession = .shared, completion: @escaping (Result<URL, Error>) -> Void)` (completion on main queue)
  - `enum AudioCacheError: Error, Equatable { case badStatus(Int); case noFile }`

- [ ] **Step 1: Write the failing test** — `Tests/CoffitivityKitTests/AudioCacheTests.swift`

```swift
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
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter AudioCacheTests`
Expected: FAIL — `cannot find 'AudioCache' in scope`.

- [ ] **Step 3: Implement `AudioCache`** — `Sources/CoffitivityKit/AudioCache.swift`

```swift
import Foundation

public enum AudioCacheError: Error, Equatable {
    case badStatus(Int)
    case noFile
}

public final class AudioCache {
    public let cacheDirectory: URL
    private let fileManager: FileManager

    public init(cacheDirectory: URL, fileManager: FileManager = .default) {
        self.cacheDirectory = cacheDirectory
        self.fileManager = fileManager
    }

    public convenience init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.init(cacheDirectory: base.appendingPathComponent("CoffitivityLocal", isDirectory: true))
    }

    public func localURL(for sound: Sound) -> URL {
        cacheDirectory.appendingPathComponent("\(sound.id).mp3")
    }

    public func isCached(_ sound: Sound) -> Bool {
        fileManager.fileExists(atPath: localURL(for: sound).path)
    }

    /// Atomically move a freshly downloaded temp file into the cache. Returns the cached URL.
    @discardableResult
    public func store(downloadedFile tempURL: URL, for sound: Sound) throws -> URL {
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let dest = localURL(for: sound)
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }
        try fileManager.moveItem(at: tempURL, to: dest)
        return dest
    }

    /// Download the sound's mp3 and cache it. `completion` is delivered on the main queue.
    public func download(_ sound: Sound,
                         session: URLSession = .shared,
                         completion: @escaping (Result<URL, Error>) -> Void) {
        let task = session.downloadTask(with: sound.url) { [weak self] tempURL, response, error in
            let result: Result<URL, Error>
            if let error = error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                result = .failure(AudioCacheError.badStatus(http.statusCode))
            } else if let tempURL = tempURL, let self = self {
                do { result = .success(try self.store(downloadedFile: tempURL, for: sound)) }
                catch { result = .failure(error) }
            } else {
                result = .failure(AudioCacheError.noFile)
            }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter AudioCacheTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CoffitivityKit/AudioCache.swift Tests/CoffitivityKitTests/AudioCacheTests.swift
git commit -m "feat: add AudioCache with atomic store and background download"
```

---

### Task 3: `Player` — looping AVAudioPlayer wrapper

**Files:**
- Create: `Sources/CoffitivityKit/Player.swift`
- Test: `Tests/CoffitivityKitTests/PlayerTests.swift`

**Interfaces:**
- Consumes: nothing (takes a local `URL` + `id`).
- Produces:
  - `final class Player` with `init(volume: Float = 0.7)`.
  - `var nowPlaying: String?` (read-only outside) — id of the playing sound, or nil.
  - `var volume: Float` (read-only outside), always clamped to `0...1`.
  - `@discardableResult func play(localURL: URL, id: String) -> Bool` — loops forever (`numberOfLoops = -1`); replaces any current playback; returns false if the file can't be opened.
  - `func stop()`
  - `func setVolume(_ v: Float)` — clamps and applies live.

- [ ] **Step 1: Write the failing test** — `Tests/CoffitivityKitTests/PlayerTests.swift`

```swift
import XCTest
@testable import CoffitivityKit

final class PlayerTests: XCTestCase {
    func testNowPlayingIsNilInitially() {
        XCTAssertNil(Player().nowPlaying)
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
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter PlayerTests`
Expected: FAIL — `cannot find 'Player' in scope`.

- [ ] **Step 3: Implement `Player`** — `Sources/CoffitivityKit/Player.swift`

```swift
import Foundation
import AVFoundation

public final class Player {
    private var player: AVAudioPlayer?
    public private(set) var nowPlaying: String?
    public private(set) var volume: Float

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
            return true
        } catch {
            return false
        }
    }

    public func stop() {
        player?.stop()
        player = nil
        nowPlaying = nil
    }

    public func setVolume(_ v: Float) {
        volume = Player.clamp(v)
        player?.volume = volume
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter PlayerTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Run the whole suite**

Run: `swift test`
Expected: PASS (all tests from Tasks 1–3).

- [ ] **Step 6: Commit**

```bash
git add Sources/CoffitivityKit/Player.swift Tests/CoffitivityKitTests/PlayerTests.swift
git commit -m "feat: add looping AVAudioPlayer wrapper with clamped volume"
```

---

### Task 4: Menu-bar app — controller, bootstrap, packaging (play / stop / download)

This task produces a runnable `.app`. It has no automated tests (AppKit + audio + network); its deliverable is verified by the manual smoke test in Step 8, which is this task's gate.

**Files:**
- Create: `Sources/CoffitivityKit/StatusItemController.swift`
- Create: `Sources/CoffitivityLocal/AppDelegate.swift`
- Create: `Sources/CoffitivityLocal/main.swift`
- Create: `Info.plist`
- Create: `make-app.sh`

**Interfaces:**
- Consumes: `Sound.all` (Task 1), `AudioCache` (Task 2), `Player` (Task 3).
- Produces: `public final class StatusItemController` with `public init(cache: AudioCache = AudioCache(), defaults: UserDefaults = .standard)`. (In this task `init` creates the `Player` with the fixed default volume `0.7`; Task 5 adds the slider and persistence.)

- [ ] **Step 1: Implement `StatusItemController`** — `Sources/CoffitivityKit/StatusItemController.swift`

```swift
import AppKit

public final class StatusItemController {
    private let statusItem: NSStatusItem
    private let player: Player
    private let cache: AudioCache

    private var downloadingId: String?
    private var soundItems: [String: NSMenuItem] = [:]

    public init(cache: AudioCache = AudioCache(), defaults: UserDefaults = .standard) {
        self.cache = cache
        self.player = Player(volume: 0.7)
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        statusItem.menu = buildMenu()
        refreshStates()
    }

    private func configureButton() {
        statusItem.button?.image = NSImage(systemSymbolName: "cup.and.saucer.fill",
                                           accessibilityDescription: "Coffitivity")
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
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
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func sound(for id: String) -> Sound? {
        Sound.all.first { $0.id == id }
    }

    @objc private func soundClicked(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String, let sound = sound(for: id) else { return }
        if player.nowPlaying == id {
            player.stop()
            refreshStates()
        } else if cache.isCached(sound) {
            playCached(sound)
        } else {
            startDownload(sound)
        }
    }

    private func playCached(_ sound: Sound) {
        player.play(localURL: cache.localURL(for: sound), id: sound.id)
        refreshStates()
    }

    private func startDownload(_ sound: Sound) {
        downloadingId = sound.id
        refreshStates()
        cache.download(sound) { [weak self] result in
            guard let self = self else { return }
            self.downloadingId = nil
            switch result {
            case .success:
                self.playCached(sound)
            case .failure:
                self.refreshStates()
                self.showDownloadError(sound)
            }
        }
    }

    private func refreshStates() {
        for sound in Sound.all {
            guard let item = soundItems[sound.id] else { continue }
            if sound.id == downloadingId {
                item.title = "\(sound.name)  (downloading…)"
                item.state = .off
                item.isEnabled = false
            } else {
                item.title = sound.name
                item.state = (player.nowPlaying == sound.id) ? .on : .off
                item.isEnabled = true
            }
        }
    }

    private func showDownloadError(_ sound: Sound) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t download “\(sound.name)”"
        alert.informativeText = "Check your internet connection and try again."
        alert.alertStyle = .warning
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
```

- [ ] **Step 2: Implement `AppDelegate`** — `Sources/CoffitivityLocal/AppDelegate.swift`

```swift
import AppKit
import CoffitivityKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = StatusItemController()
    }
}
```

- [ ] **Step 3: Implement `main.swift`** — `Sources/CoffitivityLocal/main.swift`

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 4: Create `Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>CoffitivityLocal</string>
    <key>CFBundleDisplayName</key>
    <string>Coffitivity Local</string>
    <key>CFBundleIdentifier</key>
    <string>xyz.joystudios.coffitivity-local</string>
    <key>CFBundleExecutable</key>
    <string>CoffitivityLocal</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 5: Create `make-app.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CoffitivityLocal"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"

swift build -c release

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

echo "Built $APP_BUNDLE — open it with: open \"$APP_BUNDLE\""
```

- [ ] **Step 6: Make the script executable and build the app**

Run:
```bash
chmod +x make-app.sh
./make-app.sh
```
Expected: `swift build -c release` succeeds and prints `Built CoffitivityLocal.app`.

- [ ] **Step 7: Launch**

Run: `open CoffitivityLocal.app`
Expected: a coffee-cup icon appears in the macOS menu bar; no Dock icon, no window.

- [ ] **Step 8: Manual smoke test (this task's gate)**

Verify each, with the network ON:
- Clicking the menu-bar icon opens a menu listing the 9 sounds + Quit.
- Clicking a sound shows "(downloading…)" briefly, then it starts playing and gets a ✓.
- The sound loops seamlessly (let it run past the track length, or pick White Noise — it's short — and confirm it repeats without stopping).
- Clicking the playing sound stops it (✓ clears).
- Clicking a different sound stops the first and plays the second (only one ✓ at a time).
- A sound played once shows no "(downloading…)" the second time (served from cache).

Then verify offline behavior:
- Quit Wi-Fi/network. Click an already-played sound → it still plays (from cache).
- Click a sound you have **not** played yet → an alert "Couldn’t download …" appears; no crash; that item does not get a ✓.

- [ ] **Step 9: Commit**

```bash
git add Sources/CoffitivityKit/StatusItemController.swift \
        Sources/CoffitivityLocal/AppDelegate.swift \
        Sources/CoffitivityLocal/main.swift Info.plist make-app.sh
git commit -m "feat: menu-bar app that plays, loops, and caches free sounds"
```

---

### Task 5: Volume slider + persistence + README

**Files:**
- Modify: `Sources/CoffitivityKit/StatusItemController.swift`
- Create: `README.md`

**Interfaces:**
- Consumes: `Player.setVolume` (Task 3), `StatusItemController` (Task 4).
- Produces: a volume `NSSlider` in the menu; volume read from and written to `UserDefaults` key `volume` (default `0.7`).

- [ ] **Step 1: Read the saved volume at init** — in `StatusItemController.init`, replace the fixed-volume Player creation.

Replace:
```swift
        self.cache = cache
        self.player = Player(volume: 0.7)
```
with:
```swift
        self.cache = cache
        self.defaults = defaults
        let savedVolume = defaults.object(forKey: Self.volumeKey) as? Float ?? 0.7
        self.player = Player(volume: savedVolume)
```

Add these stored properties alongside the others (below `private var soundItems`):
```swift
    private let defaults: UserDefaults
    private static let volumeKey = "volume"
```

- [ ] **Step 2: Add the slider to the menu** — in `buildMenu()`, insert the volume item between the sounds loop and the `Quit` separator block. After the `for sound in Sound.all { ... }` loop and before the existing `menu.addItem(.separator())`, add:

```swift
        menu.addItem(.separator())
        menu.addItem(makeVolumeItem())
```

(The existing separator + Quit stay as they are, so the order is: sounds, separator, volume, separator, Quit.)

- [ ] **Step 3: Implement the slider item + handler** — add these methods to `StatusItemController`:

```swift
    private func makeVolumeItem() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
        let slider = NSSlider(value: Double(player.volume), minValue: 0, maxValue: 1,
                              target: self, action: #selector(volumeChanged(_:)))
        slider.frame = NSRect(x: 20, y: 4, width: 160, height: 20)
        container.addSubview(slider)
        let item = NSMenuItem()
        item.view = container
        return item
    }

    @objc private func volumeChanged(_ slider: NSSlider) {
        let v = Float(slider.doubleValue)
        player.setVolume(v)
        defaults.set(v, forKey: Self.volumeKey)
    }
```

- [ ] **Step 4: Rebuild**

Run: `./make-app.sh`
Expected: build succeeds.

- [ ] **Step 5: Manual smoke test (this task's gate)**

- `open CoffitivityLocal.app`; open the menu — a volume slider sits below the sounds.
- Play a sound; drag the slider — loudness changes live.
- Set the slider to a distinctive level (e.g. near minimum). Quit the app (Quit menu item).
- Relaunch `open CoffitivityLocal.app`; open the menu — the slider is back at the level you left it (Review Focus: volume persists across relaunch).

- [ ] **Step 6: Create `README.md`**

```markdown
# Coffitivity Local

A tiny macOS menu-bar app that loops the 9 free ambience tracks from
[coffitivity.com/library/free](https://coffitivity.com/library/free).

- Lives in the menu bar (no Dock icon, no window).
- Click the coffee-cup icon, pick a sound — it loops as background ambience.
- Each sound downloads and caches on first play, then works offline.
- Volume slider, remembered across launches.

## Build

Requires macOS 13+ and a Swift 5.9+ toolchain (Xcode or the Swift toolchain).

```bash
./make-app.sh
open CoffitivityLocal.app
```

`make-app.sh` builds a release binary and bundles it into `CoffitivityLocal.app`,
which you can move to `/Applications`. To quit, use the Quit item in the menu.

## Develop

```bash
swift test   # runs the CoffitivityKit unit tests
swift run CoffitivityLocal   # run without bundling
```

Cached audio lives in `~/Library/Application Support/CoffitivityLocal/`.

## Scope

Plays the free library only. No mixing, accounts, or premium sounds — by design.
```

- [ ] **Step 7: Confirm the unit suite still passes**

Run: `swift test`
Expected: PASS (all tests).

- [ ] **Step 8: Commit**

```bash
git add Sources/CoffitivityKit/StatusItemController.swift README.md
git commit -m "feat: add persisted volume slider and README"
```

---

## Done

After Task 5: a small `CoffitivityLocal.app` that lists the 9 free sounds in the
menu bar, loops the selected one, caches on first play for offline use, and has a
remembered volume — built with no third-party dependencies and covered by
`swift test` for its pure logic.

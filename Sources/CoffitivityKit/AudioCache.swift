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

    /// Remove all cached audio by deleting the cache directory. A later `store`
    /// recreates it. Safe to call when nothing has been cached yet.
    public func clear() throws {
        if fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.removeItem(at: cacheDirectory)
        }
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

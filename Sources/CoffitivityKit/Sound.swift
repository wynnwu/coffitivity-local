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

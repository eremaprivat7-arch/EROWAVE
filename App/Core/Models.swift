import Foundation

struct MusicTrack: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    var artworkURL: URL? = nil
    var previewURL: URL? = nil // Legacy decoding. Never used as an entitlement.
    let source: String
    var externalURL: URL? = nil
    var album: String? = nil
    var year: String? = nil
    var isrc: String? = nil
    var seconds: Double? = nil
    var asset: Int? = nil
    var audioURL: URL? = nil
    var albumID: String? = nil
    var artistID: String? = nil
    var genre: String? = nil
    var released: String? = nil
    var localFile: String? = nil
    var canPlay: Bool { asset != nil || localURL != nil || (source == "Audius" && audioURL?.host == "api.audius.co") }
    var artistImage: URL? = nil
    var artistBio: String? = nil
    var verified: Bool? = nil
    var artistLink: URL? = nil
    var localURL: URL? {
        guard source == "On this iPhone", let localFile, localFile == (localFile as NSString).lastPathComponent else { return nil }
        return URL.applicationSupportDirectory.appending(path:"Audio").appending(path:localFile)
    }
    var playableURL: URL? {
        if let localURL { return localURL }
        if let asset { return Bundle.main.url(forResource: "cut\(asset)", withExtension: "m4a") }
        return canPlay ? audioURL : nil
    }
    static let originals: [MusicTrack] = ["Undertow", "Silver Hours", "Night Transit"].enumerated().map { index, name in
        MusicTrack(id: "wave:\(index)", title: name, artist: "ERØWAVE Studio", source: "Studio original", album: "After Hours", year: "2026", seconds: 64 * 60 / [78.0, 90, 104][index], asset: index)
    }
}

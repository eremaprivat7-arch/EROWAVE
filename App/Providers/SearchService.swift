import Foundation

protocol MusicCatalog: Sendable {
    var name: String { get }
    func search(_ query: String, page: Int) async throws -> [MusicTrack]
}
struct ITunesCatalog: MusicCatalog {
    let name = "iTunes"
    struct Response: Decodable { let results: [Item] }
    struct Item: Decodable {
        let trackId: Int?, trackName: String?, artistName: String?, trackViewUrl: URL?, collectionName: String?, collectionId: Int?, artistId: Int?, releaseDate: String?, trackTimeMillis: Double?
        var track: MusicTrack? {
            guard let trackId, let trackName, let trackViewUrl else { return nil }
            return MusicTrack(id: "itunes:\(trackId)", title: trackName, artist: artistName ?? "Unknown artist", source: "iTunes", externalURL: trackViewUrl, album: collectionName, year: releaseDate.map { String($0.prefix(4)) }, seconds: trackTimeMillis.map { $0 / 1000 }, albumID: collectionId.map { String($0) }, artistID: artistId.map { String($0) })
        }
    }
    static var country: String { Locale.current.region?.identifier.lowercased() ?? "us" }
    func search(_ query: String, page: Int) async throws -> [MusicTrack] {
        guard page == 0 else { return [] }
        return try await CatalogHTTP.shared.get("https://itunes.apple.com/search", queryItems(["term":query,"entity":"song","country":Self.country,"limit":"25"]), as: Response.self).results.compactMap(\.track)
    }
    static func details(id: String) async throws -> [MusicTrack] {
        try await CatalogHTTP.shared.get("https://itunes.apple.com/lookup", queryItems(["id":id,"entity":"song","country":country,"limit":"200"]), as: Response.self).results.compactMap(\.track)
    }
}

struct MusicBrainzCatalog: MusicCatalog {
    let name = "MusicBrainz"
    struct Response: Decodable { let recordings: [Recording] }
    struct Recording: Decodable {
        let id: String, title: String, credits: [Credit]?, releases: [Release]?, isrcs: [String]?, length: Double?
        enum CodingKeys: String, CodingKey { case id,title,releases,isrcs,length; case credits = "artist-credit" }
    }
    struct Credit: Decodable { let name: String?, joinphrase: String? }
    struct Release: Decodable { let title: String?, date: String? }
    func search(_ query: String, page: Int) async throws -> [MusicTrack] {
        let words = query.split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
        guard !words.isEmpty else { return [] }
        let rows = try await CatalogHTTP.shared.get("https://musicbrainz.org/ws/2/recording", queryItems(["query":words,"fmt":"json","limit":"25","offset":String(page * 25)]), as: Response.self)
        return rows.recordings.map { item in
            MusicTrack(id: "mb:\(item.id)", title: item.title, artist: item.credits?.map { ($0.name ?? "") + ($0.joinphrase ?? "") }.joined() ?? "Unknown artist", source: name, externalURL: URL(string:"https://musicbrainz.org/recording/\(item.id)"), album:item.releases?.first?.title, year:item.releases?.first?.date.map { String($0.prefix(4)) }, isrc:item.isrcs?.first, seconds:item.length.map { $0/1000 })
        }
    }
}
struct ArchiveCatalog: MusicCatalog {
    let name = "Internet Archive"
    struct Envelope: Decodable { let response: Page }
    struct Page: Decodable { let docs: [Item] }
    struct Item: Decodable {
        let identifier: String, title: String?
    }
    func search(_ query: String, page: Int) async throws -> [MusicTrack] {
        let words = query.split { !$0.isNumber && !$0.isLetter }.joined(separator: " ")
        guard !words.isEmpty else { return [] }
        let result = try await CatalogHTTP.shared.get("https://archive.org/advancedsearch.php",queryItems(["q":"mediatype:audio AND (title:\"\(words)\" OR creator:\"\(words)\")","fl[]":"identifier,title","rows":"25","page":String(page+1),"output":"json"]),as:Envelope.self)
        return result.response.docs.compactMap { item in
            guard let title = item.title else { return nil }
            return MusicTrack(id:"ia:\(item.identifier)",title:title,artist:"Archive audio item",source:name,externalURL:URL(string:"https://archive.org/details/")?.appendingPathComponent(item.identifier))
        }
    }
}
struct AudiusCatalog: MusicCatalog {
    let name = "Audius"
    struct Envelope: Decodable { let data: [Item] }
    struct User: Decodable { let name: String; let handle: String?, bio: String?, is_verified: Bool?, profile_picture: [String:String]? }
    struct Item: Decodable {
        let id: String, title: String, user: User, permalink: String?, duration: Double?, artwork: [String:String]?, is_streamable: Bool?, is_stream_gated: Bool?, is_available: Bool?, isrc: String?, genre: String?, release_date: String?
        var track: MusicTrack? {
            guard let permalink, permalink.hasPrefix("/"), !permalink.hasPrefix("//") else { return nil }
            let allowed = is_streamable == true && is_stream_gated == false && is_available != false
            return MusicTrack(id:"audius:\(id)",title:title,artist:user.name,artworkURL:artwork?["480x480"].flatMap(URL.init(string:)),source:"Audius",externalURL:URL(string:"https://audius.co"+permalink),isrc:isrc,seconds:duration,audioURL:allowed ? URL(string:"https://api.audius.co/v1/tracks/\(id)/stream?app_name=EROWAVE") : nil,genre:genre,released:release_date,artistImage:user.profile_picture?["480x480"].flatMap(URL.init(string:)),artistBio:user.bio,verified:user.is_verified,artistLink:user.handle.flatMap { URL(string:"https://audius.co/")?.appendingPathComponent($0) })
        }
    }
    func search(_ query: String, page: Int) async throws -> [MusicTrack] {
        try await CatalogHTTP.shared.get("https://api.audius.co/v1/tracks/search",queryItems(["query":query,"limit":"25","offset":String(page*25),"app_name":"EROWAVE"]),as:Envelope.self).data.compactMap(\.track)
    }
    func trending() async throws -> [MusicTrack] {
        try await CatalogHTTP.shared.get("https://api.audius.co/v1/tracks/trending",queryItems(["time":"week","limit":"12","app_name":"EROWAVE"]),as:Envelope.self).data.compactMap(\.track)
    }
}

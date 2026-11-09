import Foundation

struct CatalogEntity: Identifiable, Sendable {
    let source: String
    let providerID: String
    let title: String
    let subtitle: String
    let album: Bool
    let url: URL
    var id: String { source + ":" + providerID }
    var seed: MusicTrack {
        MusicTrack(id:"entity:"+id,title:title,artist:album ? subtitle:title,source:source,externalURL:url,album:album ? title:nil,albumID:album ? providerID:nil,artistID:album ? nil:providerID)
    }
}
enum EntityCatalog {
    struct StoreResponse: Decodable { let results: [StoreEntity] }
    struct StoreEntity: Decodable {
        let artistId:Int?, collectionId:Int?, artistName:String?, collectionName:String?, artistLinkUrl:URL?, artistViewUrl:URL?, collectionViewUrl:URL?, primaryGenreName:String?
    }
    struct BrainzResponse: Decodable { let artists:[BrainzEntity]?, releases:[BrainzEntity]? }
    struct BrainzEntity: Decodable {
        let id:String, name:String?, title:String?, disambiguation:String?, credits:[MusicBrainzCatalog.Credit]?
        enum CodingKeys:String,CodingKey { case id,name,title,disambiguation; case credits="artist-credit" }
    }
    static func store(_ query:String, album:Bool) async throws -> [CatalogEntity] {
        let params=queryItems(["term":query,"country":ITunesCatalog.country,"entity":album ? "album":"musicArtist","limit":"25"])
        let response=try await CatalogHTTP.shared.get("https://itunes.apple.com/search",params,as:StoreResponse.self)
        return response.results.compactMap { row in
            guard let id=album ? row.collectionId:row.artistId,let title=album ? row.collectionName:row.artistName,
                  let url=album ? row.collectionViewUrl:(row.artistLinkUrl ?? row.artistViewUrl) else { return nil }
            return CatalogEntity(source:"iTunes",providerID:String(id),title:title,subtitle:(album ? row.artistName:row.primaryGenreName) ?? "",album:album,url:url)
        }
    }
    static func brainz(_ query:String, album:Bool) async throws -> [CatalogEntity] {
        let type=album ? "release":"artist"
        let words=query.split { !$0.isLetter && !$0.isNumber }.joined(separator:" ")
        guard !words.isEmpty else { return [] }
        let response=try await CatalogHTTP.shared.get("https://musicbrainz.org/ws/2/"+type,queryItems(["query":words,"fmt":"json","limit":"25"]),as:BrainzResponse.self)
        return (response.artists ?? response.releases ?? []).compactMap { row in
            guard let title=row.title ?? row.name,let url=URL(string:"https://musicbrainz.org/"+type+"/"+row.id) else { return nil }
            let artist=row.credits?.map { ($0.name ?? "")+($0.joinphrase ?? "") }.joined()
            return CatalogEntity(source:"MusicBrainz",providerID:row.id,title:title,subtitle:artist ?? row.disambiguation ?? "",album:album,url:url)
        }
    }
    private struct DiscResponse:Decodable {
        let title:String, date:String?, media:[Medium]?
        struct Medium:Decodable { let tracks:[Track]? }
        struct Track:Decodable {
            let title:String, length:Double?, recording:Recording?
            struct Recording:Decodable { let id:String, title:String? }
        }
    }
    static func recordings(_ entity:CatalogEntity) async throws -> [MusicTrack] {
        if entity.source=="iTunes" { return try await ITunesCatalog.details(id:entity.providerID) }
        if !entity.album {
            let response=try await CatalogHTTP.shared.get("https://musicbrainz.org/ws/2/recording",queryItems(["artist":entity.providerID,"fmt":"json","limit":"50"]),as:MusicBrainzCatalog.Response.self)
            return response.recordings.map { r in MusicTrack(id:"mb:"+r.id,title:r.title,artist:entity.title,source:entity.source,externalURL:URL(string:"https://musicbrainz.org/recording/"+r.id),seconds:r.length.map { $0/1000 },artistID:entity.providerID) }
        }
        let url="https://musicbrainz.org/ws/2/release/"+entity.providerID
        let record=try await CatalogHTTP.shared.get(url,queryItems(["inc":"recordings","fmt":"json"]),as:DiscResponse.self)
        return (record.media ?? []).flatMap { $0.tracks ?? [] }.compactMap { t in
            guard let r=t.recording else { return nil }
            return MusicTrack(id:"mb:"+r.id,title:t.title,artist:entity.subtitle,source:entity.source,externalURL:URL(string:"https://musicbrainz.org/recording/"+r.id),album:record.title,year:record.date.map { String($0.prefix(4)) },seconds:t.length.map { $0/1000 },albumID:entity.providerID)
        }
    }
}

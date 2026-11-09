import Foundation

struct LibraryOfCongressCatalog: MusicCatalog {
    let name = "Library of Congress"
    private struct Page: Decodable { let results: [Item] }
    private struct Item: Decodable {
        let id: String
        let title: String?
        let contributor: [String]?
        let date: String?
    }
    func search(_ query: String, page: Int) async throws -> [MusicTrack] {
        let params = queryItems(["q":query,"fo":"json","c":"25","sp":String(page+1),"at":"results"])
        let page = try await CatalogHTTP.shared.get("https://www.loc.gov/audio/",params,as:Page.self)
        return page.results.compactMap { item in
            guard let title=item.title,var url=URLComponents(string:item.id),
                  ["www.loc.gov","loc.gov"].contains(url.host ?? "") else { return nil }
            url.scheme="https"
            return MusicTrack(id:"loc:"+item.id,title:title,artist:item.contributor?.joined(separator:", ") ?? "Library recording",source:name,externalURL:url.url,year:item.date.map { String($0.prefix(4)) })
        }
    }
}

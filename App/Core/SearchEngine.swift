import Foundation
import Combine

struct SearchPage: Sendable {
    var tracks: [MusicTrack] = []
    var failed: [String] = []
    var more = false
}
actor SearchEngine {
    static let shared=SearchEngine()
    func clear() { cache.removeAll() }
    func ranked(_ rows:[MusicTrack],term:String)->[MusicTrack] { Self.rank(rows,term:term) }
    let catalogs: [any MusicCatalog]
    private var cache: [String: (Date,SearchPage)] = [:]
    init(_ catalogs: [any MusicCatalog] = [AudiusCatalog(), ITunesCatalog(), MusicBrainzCatalog(), ArchiveCatalog(), LibraryOfCongressCatalog()]) { self.catalogs = catalogs }
    static func normal(_ s: String) -> String { s.folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"en_US_POSIX")).split { !$0.isNumber && !$0.isLetter }.joined(separator:" ") }
    static func rank(_ tracks: [MusicTrack], term: String) -> [MusicTrack] {
        let query = normal(term)
        func grams(_ s:String) -> Set<String> {
            let letters=Array(s)
            guard letters.count>2 else { return [s] }
            return Set((0..<(letters.count-2)).map { String(letters[$0...($0+2)]) })
        }
        let wanted=grams(query)
        func score(_ t: MusicTrack) -> Int {
            let title = normal(t.title), artist = normal(t.artist)
            let hits = query.split(separator:" ").filter { (title+" "+artist).contains($0) }.count
            let candidate=grams(title+" "+artist)
            let similarity=6 * wanted.intersection(candidate).count / max(1,wanted.count)
            return similarity + (title == query ? 20 : 0) + (artist == query ? 12 : 0) + hits*3 + (t.canPlay ? 1 : 0)
        }
        var seen = Set<String>()
        return tracks.map { ($0,score($0)) }.sorted { a,b in
            a.1 == b.1 ? a.0.id < b.0.id : a.1 > b.1
        }.map { $0.0 }.filter { t in
            var key = t.id
            if let isrc=t.isrc, !isrc.isEmpty, let duration=t.seconds {
                key = [isrc.uppercased(), normal(t.artist), normal(t.title), String(Int(duration.rounded()))].joined(separator:"|")
            }
            return seen.insert(key).inserted
        }
    }
    func search(_ term: String, page: Int, update: (@Sendable (SearchPage) async -> Void)? = nil) async throws -> SearchPage {
        try Task.checkCancellation()
        let key = "\(page):\(term.lowercased())"
        if let hit=cache[key], Date().timeIntervalSince(hit.0)<90 { return hit.1 }
        var batch = SearchPage()
        if page == 0 { batch.tracks = MusicTrack.originals.filter { Self.normal([$0.title,$0.artist,$0.album ?? ""].joined(separator:" ")).contains(Self.normal(term)) } }
        if !batch.tracks.isEmpty { await update?(batch) }
        await withTaskGroup(of:(String,[MusicTrack]?).self) { group in
            for catalog in catalogs {
                group.addTask { (catalog.name,try? await catalog.search(term,page:page)) }
            }
            for await (name,rows) in group {
                if let rows { batch.tracks += rows; if name != "iTunes" && rows.count >= 25 { batch.more = true } }
                else { batch.failed.append(name) }
                if !Task.isCancelled { await update?(batch) }
            }
        }
        try Task.checkCancellation()
        batch.tracks = Self.rank(batch.tracks,term:term)
        if cache.count >= 40 { cache.removeAll(keepingCapacity:true) }
        if batch.failed.isEmpty { cache[key]=(Date(),batch) }
        return batch
    }
}
@MainActor final class SearchStore: ObservableObject {
    @Published var query = ""
    @Published var results = [MusicTrack]()
    @Published var failed = [String]()
    @Published var loading = false
    @Published var more = false
    private var page = 0
    private var job: Task<Void,Never>?
    private let engine: SearchEngine
    init(engine: SearchEngine = .shared) { self.engine = engine }
    func search(next: Bool = false) {
        job?.cancel()
        let term = query.trimmingCharacters(in:.whitespacesAndNewlines)
        if !next { results=[]; page=0; more=false; failed=[] }
        loading = !term.isEmpty
        guard loading else { return }
        job = Task {
            do {
                if !next { try await Task.sleep(for:.milliseconds(300)) }
                let prior=results
                let batch = try await engine.search(term,page:page) { partial in
                    let ranked = await self.engine.ranked(prior+partial.tracks,term:term)
                    await MainActor.run {
                        guard !Task.isCancelled, self.query.trimmed==term else { return }
                        self.results=ranked
                    }
                }
                try Task.checkCancellation()
                let final = await engine.ranked(prior + batch.tracks,term:term)
                try Task.checkCancellation()
                results = final
                failed=batch.failed.sorted(); more=batch.more; page += 1; loading=false
            } catch { if !Task.isCancelled { loading=false } }
        }
    }
}

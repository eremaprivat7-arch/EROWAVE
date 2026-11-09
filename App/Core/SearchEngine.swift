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
    static func normal(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX"))
        let words = folded.split { character in
            !character.isNumber && !character.isLetter
        }
        return words.joined(separator: " ")
    }

    private static func grams(_ text: String) -> Set<String> {
        let letters = Array(text)
        guard letters.count > 2 else { return [text] }
        var result = Set<String>()
        for start in 0..<(letters.count - 2) {
            let end = start + 2
            result.insert(String(letters[start...end]))
        }
        return result
    }

    static func rank(_ tracks: [MusicTrack], term: String) -> [MusicTrack] {
        let query = normal(term)
        let words = query.split(separator: " ").map { String($0) }
        let wanted = grams(query)
        var scored: [(track: MusicTrack, score: Int)] = []
        for track in tracks {
            let title = normal(track.title)
            let artist = normal(track.artist)
            let text = title + " " + artist
            let overlap = wanted.intersection(grams(text)).count
            var score: Int = 6 * overlap / max(1, wanted.count)
            for word in words where text.contains(word) { score += 3 }
            if title == query { score += 20 }
            if artist == query { score += 12 }
            if track.canPlay { score += 1 }
            scored.append((track, score))
        }

        scored.sort { left, right in
            if left.score == right.score { return left.track.id < right.track.id }
            return left.score > right.score
        }

        var seen = Set<String>()
        var result: [MusicTrack] = []
        for entry in scored {
            let track = entry.track
            var key = track.id
            if let isrc = track.isrc, !isrc.isEmpty, let duration = track.seconds {
                let seconds = String(Int(duration.rounded()))
                let fields: [String] = [isrc.uppercased(), normal(track.artist), normal(track.title), seconds]
                key = fields.joined(separator: "|")
            }
            if seen.insert(key).inserted { result.append(track) }
        }
        return result
    }
    func search(_ term: String, page: Int, update: (@Sendable (SearchPage) async -> Void)? = nil) async throws -> SearchPage {
        try Task.checkCancellation()
        let key = "\(page):\(term.lowercased())"
        if let hit=cache[key], Date().timeIntervalSince(hit.0)<90 { return hit.1 }
        var batch = SearchPage()
        if page == 0 {
            let query = Self.normal(term)
            for track in MusicTrack.originals {
                let fields: [String] = [track.title, track.artist, track.album ?? ""]
                let searchable = Self.normal(fields.joined(separator: " "))
                if searchable.contains(query) { batch.tracks.append(track) }
            }
        }
        if !batch.tracks.isEmpty { await update?(batch) }
        await withTaskGroup(of:(String,[MusicTrack]?).self) { group in
            for catalog in catalogs {
                group.addTask {
                    let rows: [MusicTrack]? = try? await catalog.search(term, page: page)
                    return (catalog.name, rows)
                }
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

import XCTest
import SwiftData
@testable import EROWAVE

private struct Stub:MusicCatalog {
    var name:String
    var rows:[MusicTrack]=[]
    var fails=false
    var wait=false
    func search(_ query:String,page:Int) async throws -> [MusicTrack] {
        if wait { try await Task.sleep(for:.seconds(10)) }
        if fails { throw URLError(.notConnectedToInternet) }
        return rows
    }
}
final class EROWAVETests:XCTestCase {
    let cuts=MusicTrack.originals
    func testProviderFailurePreservesOtherResults() async throws {
        let engine=SearchEngine([Stub(name:"offline",fails:true),Stub(name:"active",rows:[cuts[0]])])
        let result=try await engine.search("different",page:0)
        XCTAssertEqual(result.tracks,[cuts[0]]); XCTAssertEqual(result.failed,["offline"])
    }
    func testAllProvidersFailAndEmptyCatalog() async throws {
        let a=try await SearchEngine([Stub(name:"down",fails:true)]).search("nobody",page:0)
        let b=try await SearchEngine([Stub(name:"up")]).search("nobody",page:0)
        XCTAssertTrue(a.tracks.isEmpty); XCTAssertEqual(a.failed,["down"]); XCTAssertTrue(b.tracks.isEmpty); XCTAssertTrue(b.failed.isEmpty)
    }
    func testSafeDeduplication() {
        func row(_ id:String,_ title:String,_ duration:Double=100)->MusicTrack { MusicTrack(id:id,title:title,artist:"Era",source:"Catalog",isrc:"1234",seconds:duration) }
        let rows=[row("a","Night"),row("b","NIGHT"),row("c","Night (Live)"),row("d","Night",80)]
        XCTAssertEqual(SearchEngine.rank(rows,term:"Night").count,3)
        XCTAssertEqual(SearchEngine.rank([cuts[0],cuts[0]],term:"").count,1)
    }
    func testCancelInFlight() async {
        let engine=SearchEngine([Stub(name:"slow",wait:true)])
        let t=Task { try await engine.search("after",page:0) }
        try? await Task.sleep(for:.milliseconds(30)); t.cancel()
        do { _=try await t.value; XCTFail("Cancelled query returned data") } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testQueueAndArchiveRestoration() throws {
        var q=SessionSnapshot(current:cuts[0],upcoming:[cuts[1],cuts[2]])
        XCTAssertEqual(q.advance(ended:true),cuts[1]); XCTAssertEqual(q.previous,[cuts[0]])
        q.loop = .one; XCTAssertEqual(q.advance(ended:true),cuts[1])
        XCTAssertEqual(q.advance(ended:false),cuts[2]); q.loop = .all
        XCTAssertEqual(q.advance(ended:true),cuts[0]); q.position=12.5
        let restored=try JSONDecoder().decode(SessionSnapshot.self,from:JSONEncoder().encode(q))
        XCTAssertEqual(restored.position,12.5); XCTAssertEqual(restored.current,cuts[0]); XCTAssertEqual(restored.upcoming,q.upcoming)
    }
    func testShuffleSelectsAvailableTrack() {
        var q=SessionSnapshot(current:cuts[0],upcoming:[cuts[1],cuts[2]],shuffle:true)
        XCTAssertEqual(q.advance(ended:true,choice:{ $0.upperBound-1 }),cuts[2]); XCTAssertEqual(q.upcoming,[cuts[1]])
    }
    @MainActor func testLibraryReopensOnDisk() throws {
        let dir=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:dir) }
        let config=ModelConfiguration(url:dir.appending(path:"test.store"))
        do {
            let first=try ModelContainer(for:CollectionRecord.self,configurations:config)
            let shelf=Shelf(first.mainContext)
            shelf.toggle("liked","Liked Songs","system",cuts[0])
            shelf.save("list","Night","playlist",cuts)
            shelf.save("list","Reordered","playlist",Array(cuts.reversed()))
            XCTAssertNil(shelf.error)
        }
        let second=try ModelContainer(for:CollectionRecord.self,configurations:config)
        let shelf=Shelf(second.mainContext)
        XCTAssertTrue(shelf.has("liked",cuts[0])); XCTAssertEqual(shelf.get("list")?.title,"Reordered")
        XCTAssertEqual(shelf.tracks("list"),Array(cuts.reversed())); shelf.toggle("liked","Liked Songs","system",cuts[0]); XCTAssertTrue(shelf.tracks("liked").isEmpty)
        shelf.remove(try XCTUnwrap(shelf.get("list"))); XCTAssertNil(shelf.get("list"))
    }
    func testLegacyPreviewIsNeverPlayed() {
        let t=MusicTrack(id:"legacy",title:"Sample",artist:"A",previewURL:URL(string:"https://example.org/preview"),source:"iTunes")
        XCTAssertFalse(t.canPlay); XCTAssertNil(t.playableURL)
    }
    func testTimedLyrics() {
        let lines=LyricLine.parse("[00:10.50][00:12.00]Two\n[00:01]One\n[ar:Artist]")
        XCTAssertEqual(lines.map(\.time),[1,10.5,12]); XCTAssertEqual(lines.map(\.text),["One","Two","Two"])
    }
}

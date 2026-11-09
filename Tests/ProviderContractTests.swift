import XCTest
@testable import EROWAVE

final class ProviderContractTests:XCTestCase {
    func testGatedAndUnknownAccessNeverGetAStream() throws {
        func decode(gate:String,available:Bool) throws -> MusicTrack {
            let json = """
            {"id":"abc","title":"Night","user":{"name":"Era"},"permalink":"/era/night","duration":120,"is_streamable":true,"is_stream_gated":\(gate),"is_available":\(available)}
            """
            let item=try JSONDecoder().decode(AudiusCatalog.Item.self,from:Data(json.utf8))
            return try XCTUnwrap(item.track)
        }
        XCTAssertFalse(try decode(gate:"true",available:true).canPlay)
        XCTAssertFalse(try decode(gate:"null",available:true).canPlay)
        XCTAssertFalse(try decode(gate:"false",available:false).canPlay)
        let open=try decode(gate:"false",available:true)
        XCTAssertTrue(open.canPlay); XCTAssertEqual(open.playableURL?.host,"api.audius.co")
    }
    func testMetadataStoreIgnoresPromotionalAssets() throws {
        let json = """
        {"results":[{"trackId":1,"trackName":"Night","artistName":"Era","trackViewUrl":"https://music.apple.com/track/1","previewUrl":"https://example.com/demo.m4a","artworkUrl100":"https://example.com/art.jpg"}]}
        """
        let item=try XCTUnwrap(JSONDecoder().decode(ITunesCatalog.Response.self,from:Data(json.utf8)).results.first?.track)
        XCTAssertFalse(item.canPlay); XCTAssertNil(item.artworkURL); XCTAssertNil(item.previewURL)
    }
    func testAudioAssetsResolveInsideBundle() throws {
        for track in MusicTrack.originals {
            let url=try XCTUnwrap(track.playableURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath:url.path))
        }
    }
}

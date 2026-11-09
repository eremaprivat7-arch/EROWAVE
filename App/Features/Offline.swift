import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct OfflineScreen:View {
    @EnvironmentObject var shelf:Shelf
    @State var importing=false
    @State var working=false
    @State var error:String?
    var body:some View {
        List {
            Section("Imported audio") {
                Button("Import from Files",systemImage:"folder") { importing=true }.disabled(working)
                if working { ProgressView("Importing audio") }
                if let error { Text(error).font(.caption) }
                TrackList(tracks:shelf.tracks("files"))
            }
            Section("Included with ERØWAVE") { TrackList(tracks:MusicTrack.originals) }
        }.navigationTitle("Offline Music").fileImporter(isPresented:$importing,allowedContentTypes:[.audio]) { result in
            do {
                let url=try result.get(); working=true; error=nil
                Task {
                    defer { working=false }
                    do {
                        let t=try await LocalImport.copy(url)
                        shelf.save("files","Imported audio","system",[t]+shelf.tracks("files"))
                    } catch { self.error=error.localizedDescription }
                }
            } catch { self.error=error.localizedDescription }
        }
    }
}
enum LocalImport {
    static func copy(_ url:URL) async throws -> MusicTrack {
        let scoped=url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let asset=AVURLAsset(url:url)
        guard try await asset.load(.isPlayable), !(try await asset.load(.hasProtectedContent)),
              !(try await asset.loadTracks(withMediaType:.audio)).isEmpty else { throw URLError(.cannotDecodeContentData) }
        let duration=try await asset.load(.duration).seconds
        let metadata=(try? await asset.load(.commonMetadata)) ?? []
        func field(_ key:AVMetadataKey) async -> String? {
            guard let item=metadata.first(where:{ $0.commonKey==key }) else { return nil }
            return try? await item.load(.stringValue)
        }
        let id=UUID().uuidString, filename=id+"."+url.pathExtension
        let dir=URL.applicationSupportDirectory.appending(path:"Audio")
        let title=await field(.commonKeyTitle) ?? url.deletingPathExtension().lastPathComponent
        let artist=await field(.commonKeyArtist) ?? "Unknown artist"
        let album=await field(.commonKeyAlbumName)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let dest=dir.appending(path:filename)
        do { try FileManager.default.copyItem(at:url,to:dest) }
        catch { try? FileManager.default.removeItem(at:dest); throw error }
        return MusicTrack(id:"file:"+id,title:title,artist:artist,source:"On this iPhone",album:album,seconds:duration.isFinite ? duration:nil,localFile:filename)
    }
}

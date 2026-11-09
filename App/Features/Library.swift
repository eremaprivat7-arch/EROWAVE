import SwiftUI

struct LibraryScreen:View {
    @EnvironmentObject var shelf:Shelf
    @State var query=""
    @State var name=""
    @State var create=false
    @State var alphabetical=false
    var lists:[CollectionRecord] {
        let found=shelf.records.filter { $0.kind=="playlist" && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
        return alphabetical ? found.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } : Array(found.reversed())
    }
    var body:some View {
        List {
            Section {
                NavigationLink { ShelfTracks(title:"Liked Songs",key:"liked") } label:{ Label("Liked Songs",systemImage:"heart.fill") }
                NavigationLink { ShelfTracks(title:"Recently Played",key:"history") } label:{ Label("Recently Played",systemImage:"clock") }
                NavigationLink { SavedEntities(album:true) } label:{ Label("Albums",systemImage:"opticaldisc") }
                NavigationLink { SavedEntities(album:false) } label:{ Label("Artists",systemImage:"person.2") }
                NavigationLink { OfflineScreen() } label:{ Label("Offline Music",systemImage:"arrow.down.circle") }
                NavigationLink { ShelfTracks(title:"Listening History",key:"events") } label:{ Label("Listening History",systemImage:"clock.arrow.circlepath") }
            }
            if !query.isEmpty {
                let songs=shelf.tracks("liked").filter { ($0.title+" "+$0.artist).localizedCaseInsensitiveContains(query) }
                if !songs.isEmpty { Section("Matching liked songs") { TrackList(tracks:songs) } }
            }
            Section {
                ForEach(lists,id:\.key) { list in NavigationLink { PlaylistScreen(key:list.key) } label:{ HStack { Image(systemName:"music.note.list"); Text(list.title); Spacer(); Text("\(list.tracks.count)").foregroundStyle(.secondary) } } }
                Button("New Playlist",systemImage:"plus") { name=""; create=true }
            } header:{ HStack { Text("Playlists"); Spacer(); Button(alphabetical ? "A–Z":"Newest first") { alphabetical.toggle() } } }
        }.navigationTitle("Your Library").searchable(text:$query,prompt:"Find saved music").scrollContentBackground(.hidden)
            .alert("New Playlist",isPresented:$create) { TextField("Playlist name",text:$name); Button("Create") { shelf.save(UUID().uuidString,name.trimmed,"playlist",[]) }.disabled(name.trimmed.isEmpty); Button("Cancel",role:.cancel) {} }
    }
}
extension String { var trimmed:String { trimmingCharacters(in:.whitespacesAndNewlines) } }
struct ShelfTracks:View {
    let title:String,key:String
    @EnvironmentObject var shelf:Shelf
    var body:some View { ScrollView { LazyVStack(spacing:14) {
        if shelf.tracks(key).isEmpty { ContentUnavailableView(key=="liked" ? "No liked songs yet":"No listening history",systemImage:key=="liked" ? "heart":"clock",description:Text(key=="liked" ? "Use Like in a track’s menu to keep it here.":"Play a track to start your history.")) }
        if key=="events" {
            ForEach(Array(shelf.tracks(key).enumerated()),id:\.offset) { _,t in TrackRow(track:t) }
        } else { TrackList(tracks:shelf.tracks(key)) }
    }.padding() }.navigationTitle(title) }
}
struct SavedEntities:View {
    let album:Bool
    @EnvironmentObject var shelf:Shelf
    var body:some View {
        let saved=shelf.records.filter { $0.kind==(album ? "album":"artist") }
        List { ForEach(saved,id:\.key) { list in if let t=list.tracks.first { NavigationLink(list.title) { DetailScreen(seed:t,album:album) } } }
            if saved.isEmpty { ContentUnavailableView(album ? "No saved albums":"No followed artists",systemImage:"square.stack") }
        }.navigationTitle(album ? "Albums":"Artists")
    }
}
struct PlaylistPicker:View {
    let track:MusicTrack
    @EnvironmentObject var shelf:Shelf
    @Environment(\.dismiss) var dismiss
    @State var name=""
    var body:some View {
        NavigationStack { List {
            Section("New playlist") { TextField("Name",text:$name); Button("Create and add") { shelf.save(UUID().uuidString,name.trimmed,"playlist",[track]); dismiss() }.disabled(name.trimmed.isEmpty) }
            ForEach(shelf.records.filter { $0.kind=="playlist" },id:\.key) { list in Button { shelf.add(track,to:list); dismiss() } label:{ HStack { Text(list.title); Spacer(); if shelf.has(list.key,track) { Image(systemName:"checkmark") } } }.disabled(shelf.has(list.key,track)) }
        }.navigationTitle("Add to Playlist").toolbar { Button("Done") { dismiss() } } }.presentationDetents([.medium,.large])
    }
}
struct PlaylistScreen:View {
    let key:String
    @EnvironmentObject var shelf:Shelf
    @EnvironmentObject var player:PlayerStore
    @Environment(\.dismiss) var dismiss
    @State var name=""
    @State var renaming=false
    @State var deleting=false
    var body:some View {
        if let list=shelf.get(key) {
            List {
                if let first=list.tracks.first(where:\.canPlay) { Button("Play",systemImage:"play.fill") { player.play(first,following:Array(list.tracks.filter(\.canPlay).dropFirst())) } }
                ForEach(list.tracks) { t in TrackRow(track:t) }
                    .onMove { from,to in var tracks=list.tracks; tracks.move(fromOffsets:from,toOffset:to); shelf.save(key,list.title,list.kind,tracks) }
                    .onDelete { offsets in var tracks=list.tracks; tracks.remove(atOffsets:offsets); shelf.save(key,list.title,list.kind,tracks) }
                if list.tracks.isEmpty { ContentUnavailableView("Your playlist is ready",systemImage:"music.note.list",description:Text("Choose Add to Playlist from any track menu.")) }
            }.navigationTitle(list.title).toolbar {
                EditButton()
                Menu { Button("Rename") { name=list.title; renaming=true }; Button("Delete playlist",role:.destructive) { deleting=true } } label:{ Image(systemName:"ellipsis.circle") }
            }.alert("Rename Playlist",isPresented:$renaming) { TextField("Name",text:$name); Button("Save") { shelf.save(key,name.trimmed,list.kind,list.tracks) }.disabled(name.trimmed.isEmpty); Button("Cancel",role:.cancel) {} }
                .confirmationDialog("Delete this playlist?",isPresented:$deleting) { Button("Delete playlist",role:.destructive) { dismiss(); shelf.remove(list) } }
        }
    }
}

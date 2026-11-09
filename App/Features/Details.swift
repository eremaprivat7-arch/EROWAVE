import SwiftUI

struct DetailScreen:View {
    let seed:MusicTrack
    let album:Bool
    var candidates:[MusicTrack]=[]
    var entity:CatalogEntity?=nil
    @EnvironmentObject var shelf:Shelf
    @EnvironmentObject var player:PlayerStore
    @State var loaded:[MusicTrack]?
    @State var failed=false
    var title:String { album ? seed.album ?? seed.title : seed.artist }
    var key:String {
        let identifier = album ? seed.albumID ?? (seed.artist+"|"+title) : seed.artistID ?? title
        return (album ? "album:":"artist:")+seed.source+":"+identifier
    }
    var rows:[MusicTrack] {
        if let loaded,!loaded.isEmpty { return loaded }
        if seed.asset != nil { return MusicTrack.originals }
        if seed.id.hasPrefix("entity:") { return [] }
        let rows=candidates.filter { $0.source==seed.source && $0.artist==seed.artist && (!album || $0.album==seed.album && $0.albumID==seed.albumID) }
        return rows.isEmpty ? [seed]:rows
    }
    var complete:Bool { seed.asset != nil || (album && loaded != nil && !failed) }
    var body:some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:18) {
                GeometryReader { geo in
                    let y=geo.frame(in:.named("detail")).minY
                    Group {
                        if !album,let image=seed.artistImage {
                            AsyncImage(url:image) { phase in if let portrait=phase.image { portrait.resizable().scaledToFill() } else { Color(white:0.1) } }.clipShape(Circle())
                        } else { ArtworkView(track:seed,size:max(105,min(270,230+y*0.32))) }
                    }.frame(width:max(105,min(270,230+y*0.32)),height:max(105,min(270,230+y*0.32))).frame(maxWidth:.infinity,maxHeight:.infinity)
                }.frame(height:230)
                Kicker(album ? "Album":"Artist"); Text(title).font(.largeTitle.bold())
                if !album,seed.verified==true { Label("Verified on "+seed.source,systemImage:"checkmark.seal.fill").font(.caption) }
                if !album,let bio=seed.artistBio,!bio.isEmpty { Text(bio).font(.callout).foregroundStyle(.secondary) }
                if album { Text([seed.artist,seed.year].compactMap { $0 }.joined(separator:" · ")).foregroundStyle(.secondary) }
                if seed.asset != nil && !album { Text("ERØWAVE’s original instrumental sessions. Synthesizers, drum machines and slow-moving chords.").foregroundStyle(.secondary) }
                HStack {
                    if let first=rows.first(where:\.canPlay) {
                        Button("Play",systemImage:"play.fill") { player.play(first,following:Array(rows.filter(\.canPlay).dropFirst())) }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                        Button("Shuffle",systemImage:"shuffle") { let mixed=rows.filter(\.canPlay).shuffled(); if let first=mixed.first { player.play(first,following:Array(mixed.dropFirst())) } }.labelStyle(.iconOnly).buttonStyle(.bordered)
                    }
                    Button(shelf.get(key)==nil ? (album ? "Save":"Follow"):(album ? "Saved":"Following")) {
                        if let current=shelf.get(key) { shelf.remove(current) } else { shelf.save(key,title,album ? "album":"artist",[seed]) }
                    }.buttonStyle(.bordered)
                    if let url=detailURL { ShareLink(item:url).labelStyle(.iconOnly) } else { ShareLink(item:title+" · ERØWAVE").labelStyle(.iconOnly) }
                }
                if album && complete && rows.allSatisfy({ $0.seconds != nil }) { Text("\(rows.count) tracks · \(Int(rows.compactMap(\.seconds).reduce(0,+)/60)) min").font(.caption).foregroundStyle(.secondary) }
                if let url=detailURL { Link("Open in "+seed.source,destination:url).font(.callout) }
                Kicker(complete ? "Tracklist":"Available recordings")
                if seed.id.hasPrefix("entity:") && loaded==nil && !failed { ProgressView() }
                if loaded?.isEmpty==true { Text("No recordings returned by this catalog.").font(.caption) }
                if failed { Text("Catalog details are currently unavailable.").font(.caption); Button("Retry") { Task { await load() } } }
                TrackList(tracks:rows)
                if !album {
                    let albums=Dictionary(grouping:rows.filter { $0.album != nil },by:{ $0.albumID ?? $0.album ?? "" })
                    if !albums.isEmpty { Kicker("Albums"); ForEach(albums.keys.sorted(),id:\.self) { id in if let tracks=albums[id],let first=tracks.first { NavigationLink(first.album ?? "Album") { DetailScreen(seed:first,album:true,candidates:tracks) } } } }
                }
            }.padding(20)
        }.coordinateSpace(name:"detail").navigationTitle(title).navigationBarTitleDisplayMode(.inline).task(id:key) { await load() }
    }
    var detailURL:URL? {
        if let entity { return entity.url }
        if seed.id.hasPrefix("entity:") { return seed.externalURL }
        if !album,let link=seed.artistLink { return link }
        guard seed.source=="iTunes",let id=album ? seed.albumID:seed.artistID else { return nil }
        return URL(string:"https://music.apple.com/\(ITunesCatalog.country)/\(album ? "album":"artist")/\(id)")
    }
    func load() async {
        if let url=detailURL,let id=album ? seed.albumID:seed.artistID,seed.source=="MusicBrainz" || entity != nil {
            let item=entity ?? CatalogEntity(source:seed.source,providerID:id,title:title,subtitle:seed.artist,album:album,url:url)
            do { loaded=try await EntityCatalog.recordings(item); failed=false }
            catch { if !Task.isCancelled { failed=true } }
            return
        }
        guard seed.source=="iTunes",let id=album ? seed.albumID:seed.artistID else { return }
        do { let items=try await ITunesCatalog.details(id:id); try Task.checkCancellation(); loaded=items.filter { album ? $0.albumID==id : $0.artistID==id }; failed=false }
        catch { if !Task.isCancelled { failed=true } }
    }
}
struct ProfileScreen:View {
    @AppStorage("username") var name=""
    @AppStorage("recentSearches") var recent=Data()
    @EnvironmentObject var shelf:Shelf
    @State var clearing=false
    @AppStorage("wifiOnly") var wifiOnly=false
    @State var cleared=false
    var body:some View {
        Form {
            Section { HStack { Image(systemName:"person.crop.circle.fill").font(.largeTitle); TextField("Your name",text:$name) } } header:{ Text("Local profile") }
            Section("Collection") {
                NavigationLink("Favorite artists") { SavedEntities(album:false) }
                NavigationLink("Listening History") { ShelfTracks(title:"Listening History",key:"events") }
                ForEach(shelf.records.filter { $0.kind=="playlist" },id:\.key) { list in NavigationLink(list.title) { PlaylistScreen(key:list.key) } }
            }
            Section("Catalogs") { ForEach(["Audius · public streams","iTunes · store links","MusicBrainz · metadata","Internet Archive · item links","Library of Congress · item links"],id:\.self) { Text($0) } }
            Section("Streaming") {
                Toggle("Wi-Fi only for audio",isOn:$wifiOnly)
                Text("Applies when the next audio file opens.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Privacy and storage") {
                Button("Clear search and network cache") {
                    Task { await SearchEngine.shared.clear(); URLCache.shared.removeAllCachedResponses(); cleared=true }
                }
                if cleared { Text("Cache cleared").font(.caption).foregroundStyle(.secondary) }
                Text("Search terms are sent to the catalog providers. Your profile, playlists and listening history stay on this device.").font(.footnote)
                Button("Clear recent searches") { recent=Data() }.disabled(recent.isEmpty)
                Button("Clear listening history",role:.destructive) { clearing=true }.disabled(shelf.tracks("history").isEmpty)
            }
            Section("About") { LabeledContent("ERØWAVE",value:"1.0"); LabeledContent("Appearance",value:"OLED Black") }
        }.navigationTitle("Profile & Settings").confirmationDialog("Clear listening history?",isPresented:$clearing) { Button("Clear history",role:.destructive) { shelf.save("history","Recently Played","system",[]); shelf.save("events","Listening History","system",[]) } }
    }
}

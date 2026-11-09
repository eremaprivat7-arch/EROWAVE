import SwiftUI

struct HomeScreen:View {
    @EnvironmentObject var shelf:Shelf
    @AppStorage("username") var name=""
    @State var trending=[MusicTrack]()
    @State var networkError=false
    var greeting:String { let h=Calendar.current.component(.hour,from:Date()); return (h<12 ? "Good morning":h<18 ? "Good afternoon":"Good evening")+(name.isEmpty ? ".":", "+name+".") }
    var body:some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:24) {
                HStack { Kicker("ERØWAVE"); Spacer(); NavigationLink { ShelfTracks(title:"Listening History",key:"events") } label:{ Image(systemName:"clock.arrow.circlepath").frame(width:44,height:44) }.accessibilityLabel("History")
                    NavigationLink { ProfileScreen() } label:{ Image(systemName:"person.crop.circle").font(.title2).frame(width:44,height:44) }.accessibilityLabel("Profile")
                }
                Text(greeting).font(.largeTitle.bold())
                NavigationLink { DetailScreen(seed:MusicTrack.originals[0],album:true) } label:{
                    ZStack(alignment:.bottomLeading) {
                        GeometryReader { g in ArtworkView(track:MusicTrack.originals[0],size:g.size.width).frame(height:g.size.height).clipped() }
                        LinearGradient(colors:[.clear,.black.opacity(0.92)],startPoint:.center,endPoint:.bottom)
                        VStack(alignment:.leading,spacing:5) { Kicker("Studio release  /  EP"); Text("After Hours").font(.system(.largeTitle,design:.default,weight:.black)); Text("ERØWAVE Studio   ↗").font(.subheadline) }.padding(20)
                    }.frame(height:255).clipShape(RoundedRectangle(cornerRadius:20))
                }.buttonStyle(.plain)
                if !shelf.tracks("history").isEmpty { Text("Recently Played").font(.title2.bold()); TrackList(tracks:Array(shelf.tracks("history").prefix(4))) }
                Text("Late Night Vibes").font(.title2.bold()); TrackList(tracks:MusicTrack.originals)
                if !trending.isEmpty {
                    Text("Trending on Audius").font(.title2.bold()); ScrollView(.horizontal) { HStack(alignment:.top,spacing:14) { ForEach(trending) { t in NavigationLink { RecordingScreen(track:t) } label:{ VStack(alignment:.leading) { ArtworkView(track:t,size:138); Text(t.title).font(.subheadline.bold()).lineLimit(2); Text(t.artist).font(.caption).foregroundStyle(.secondary) }.frame(width:138,alignment:.leading) }.buttonStyle(.plain) } } }.scrollIndicators(.hidden)
                } else if networkError { Button("Reload Audius chart",systemImage:"arrow.clockwise") { Task { await load() } } }
                if !shelf.tracks("liked").isEmpty { Text("Your Favorite Tracks").font(.title2.bold()); TrackList(tracks:Array(shelf.tracks("liked").prefix(5))) }
                DiscoveryShelves(chart:trending)
            }.padding(20)
        }.task { if trending.isEmpty { await load() } }.refreshable { await load() }
    }
    func load() async { do { trending=try await AudiusCatalog().trending(); networkError=false } catch { if !Task.isCancelled { networkError=true } } }
}
struct RecordingScreen:View {
    let track:MusicTrack
    var body:some View { ScrollView { VStack(alignment:.leading,spacing:16) { ArtworkView(track:track,size:240); Kicker(track.source); TrackRow(track:track); NavigationLink("View artist") { DetailScreen(seed:track,album:false) } }.padding() }.navigationTitle("Recording") }
}

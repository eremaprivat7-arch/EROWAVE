import SwiftUI

enum SectionTab: String,CaseIterable { case home="Home",search="Discover",library="Library"
    var icon:String { switch self { case .home:"house"; case .search:"magnifyingglass"; case .library:"square.stack" } }
}
struct RootView: View {
    @AppStorage("didWelcome") var welcomed=false
    @EnvironmentObject var player:PlayerStore
    @Environment(\.accessibilityReduceMotion) var reduced
    @State var tab=SectionTab.home
    @StateObject var search=SearchStore()
    @Namespace var art
    var body:some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if welcomed {
                VStack(spacing:0) {
                    TabView(selection: $tab) {
                        ForEach(SectionTab.allCases, id: \.self) { item in
                            NavigationStack {
                                Group {
                                    switch item {
                                    case .home: HomeScreen()
                                    case .search: SearchScreen(store: search)
                                    case .library: LibraryScreen()
                                    }
                                }
                                .toolbar(.hidden, for: .tabBar)
                            }
                            .tabItem { Label(item.rawValue, systemImage: item.icon) }
                            .tag(item)
                        }
                    }
                    if player.track != nil && !player.showFullPlayer { MiniPlayer(art:art) }
                    HStack {
                        ForEach(SectionTab.allCases,id:\.self) { item in
                            Button { tab=item } label:{
                                VStack(spacing:4) { Image(systemName:item.icon).symbolVariant(tab==item ? .fill:.none); Text(item.rawValue).font(.caption2) }
                                    .foregroundStyle(tab==item ? .white:.gray).frame(maxWidth:.infinity,minHeight:44)
                            }.accessibilityAddTraits(tab==item ? .isSelected:[]).accessibilityIdentifier("tab."+item.rawValue)
                        }
                    }.padding(.top,5).background(.black)
                }.accessibilityHidden(player.showFullPlayer)
                if player.showFullPlayer { FullPlayerScreen(art:art).zIndex(3).transition(.move(edge:.bottom).combined(with:.opacity)) }
            } else { Onboarding { welcomed=true } }
        }.animation(reduced ? nil:.spring(duration:0.4),value:player.showFullPlayer)
            .animation(reduced ? nil:.easeOut(duration:0.18),value:tab)
            .transaction { if reduced { $0.animation=nil } }
    }
}
struct Onboarding:View {
    let finish:()->Void
    @State var index=0
    let headlines=["Welcome to\nERØWAVE.","Discover\nevery sound.","Your music.\nYour universe."]
    let copy=["Independent sound, after dark.","Search across catalogs. See where every recording comes from.","Keep your favorites and sequence your own playlists."]
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Kicker("ERØWAVE"); Spacer(); Button("Skip",action:finish) }
            TabView(selection:$index) {
                ForEach(0..<3) { i in
                    VStack(alignment:.leading,spacing:18) {
                        GeometryReader { geo in ArtworkView(track:MusicTrack.originals[i],size:min(geo.size.width,geo.size.height)).frame(maxWidth:.infinity,maxHeight:.infinity) }
                        Text(headlines[i]).font(.system(.largeTitle,design:.default,weight:.black))
                        Text(copy[i]).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }.padding(.bottom,38).tag(i)
                }
            }.tabViewStyle(.page)
            Button { if index==2 { finish() } else { withAnimation { index+=1 } } } label:{ Text(index==2 ? "Get Started":"Continue").bold().frame(maxWidth:.infinity).padding().background(.white,in:Capsule()).foregroundStyle(.black) }
        }.padding(24)
    }
}
struct TrackRow:View {
    let track:MusicTrack
    var following:[MusicTrack]=[]
    @EnvironmentObject var player:PlayerStore
    @EnvironmentObject var shelf:Shelf
    @Environment(\.openURL) var openURL
    @State var choose=false
    var body:some View {
        HStack(spacing:12) {
            Button { if track.canPlay { player.play(track,following:following) } else if let url=track.externalURL { openURL(url) } } label:{
                HStack(spacing:12) {
                    ArtworkView(track:track,size:50)
                    VStack(alignment:.leading,spacing:4) {
                        Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text(track.source+" · "+(track.canPlay ? "Full track":"Open externally")).font(.caption2).foregroundStyle(WaveStyle.muted)
                    }; Spacer()
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("track."+track.id).disabled(!track.canPlay && track.externalURL==nil)
            Menu {
                Button(shelf.has("liked",track) ? "Unlike":"Like",systemImage:"heart") { shelf.toggle("liked","Liked Songs","system",track) }
                Button("Add to Playlist",systemImage:"text.badge.plus") { choose=true }
                if track.canPlay {
                    Button("Play Next") { player.enqueue(track,first:true) }
                    Button("Add to Queue") { player.enqueue(track) }
                }
                NavigationLink("Artist") { DetailScreen(seed:track,album:false) }
                if track.album != nil { NavigationLink("Album") { DetailScreen(seed:track,album:true) } }
                if let url=track.externalURL { Link("Open in "+track.source,destination:url); ShareLink(item:url) }
            } label:{ Image(systemName:"ellipsis").frame(width:40,height:44) }.accessibilityLabel("Options for "+track.title)
        }.sheet(isPresented:$choose) { PlaylistPicker(track:track) }
    }
}
struct TrackList:View {
    let tracks:[MusicTrack]
    var body:some View { ForEach(Array(tracks.enumerated()),id:\.offset) { index,t in TrackRow(track:t,following:Array(tracks.dropFirst(index+1))) } }
}

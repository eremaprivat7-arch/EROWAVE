import SwiftUI

struct SearchScreen:View {
    @ObservedObject var store:SearchStore
    @EnvironmentObject var shelf:Shelf
    @AppStorage("recentSearches") var recentData=Data()
    @State var filter="All"
    let filters=["All","Songs","Artists","Albums","Playlists","Genres"]
    var recent:[String] { (try? JSONDecoder().decode([String].self,from:recentData)) ?? [] }
    func remember() {
        let term=store.query.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        recentData=(try? JSONEncoder().encode(Array(([term]+recent.filter { $0.caseInsensitiveCompare(term) != .orderedSame }).prefix(10)))) ?? Data()
    }
    func change(_ term:String) { store.query=term; remember() }
    var body:some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:15) {
                Kicker("Music search")
                Text("Discover").font(.largeTitle.bold())
                HStack {
                    Image(systemName:"magnifyingglass")
                    TextField("Track, artist, album…",text:$store.query).accessibilityIdentifier("query").autocorrectionDisabled().submitLabel(.search).onSubmit { remember() }
                    if !store.query.isEmpty { Button("Clear",systemImage:"xmark.circle.fill") { store.query="" }.labelStyle(.iconOnly) }
                }.padding().background(WaveStyle.surface,in:RoundedRectangle(cornerRadius:16))
                ScrollView(.horizontal) { HStack { ForEach(filters,id:\.self) { label in Button(label) { filter=label }.font(.caption.bold()).padding(.horizontal,13).padding(.vertical,9).background(filter==label ? .white:WaveStyle.card,in:Capsule()).foregroundStyle(filter==label ? .black:.white) } } }.scrollIndicators(.hidden)
                if store.query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                    if !recent.isEmpty {
                        HStack { Text("Recent Searches").font(.headline); Spacer(); Button("Clear history") { recentData=Data() }.font(.caption) }
                        ForEach(recent,id:\.self) { term in Button(term,systemImage:"clock") { change(term) } }
                    }
                    Kicker("Explore"); ForEach(["Ambient","UK garage","Jazz","ERØWAVE Studio"],id:\.self) { term in Button(term,systemImage:"arrow.up.left") { change(term) }.padding(.vertical,3) }
                } else {
                    if store.loading && store.results.isEmpty { SearchSkeleton() }
                    if !store.failed.isEmpty { Text("Unavailable · "+store.failed.joined(separator:", ")).font(.caption).foregroundStyle(.secondary); Button("Retry search") { store.search() } }
                    results
                    if store.more && !store.loading { Button("Load more") { store.search(next:true) } }
                }
            }.padding(20)
        }.onChange(of:store.query) { _,_ in store.search() }
        .onChange(of:store.loading) { _,busy in if !busy && !store.results.isEmpty { remember() } }
        .animation(.easeOut(duration:0.18),value:store.results.count)
    }
    func groups(_ key:(MusicTrack)->String?) -> [String:[MusicTrack]] {
        Dictionary(grouping:store.results.filter { key($0) != nil },by:{ key($0) ?? "" })
    }
    @ViewBuilder var results:some View {
        switch filter {
        case "Artists","Albums":
            EntityResults(query:store.query,album:filter=="Albums")
        case "Genres":
            let grouped=groups { t in filter=="Artists" ? (t.artist=="Archive audio item" ? nil:t.artist) : filter=="Albums" ? t.album:t.genre }
            ForEach(grouped.keys.sorted(),id:\.self) { name in
                if let rows=grouped[name],let first=rows.first {
                    NavigationLink { if filter=="Genres" { ScrollView { LazyVStack { TrackList(tracks:rows) }.padding() }.navigationTitle(name) } else { DetailScreen(seed:first,album:filter=="Albums",candidates:rows) } } label:{ Label(name,systemImage:filter=="Artists" ? "person.crop.circle":"square.stack").frame(maxWidth:.infinity,minHeight:44,alignment:.leading) }
                }
            }
            if grouped.isEmpty && !store.loading { empty }
        case "Playlists":
            let lists=shelf.records.filter { $0.kind=="playlist" && $0.title.localizedCaseInsensitiveContains(store.query) }
            ForEach(lists,id:\.key) { list in NavigationLink(list.title) { PlaylistScreen(key:list.key) } }
            if lists.isEmpty { ContentUnavailableView("No matching local playlists",systemImage:"music.note.list") }
        default:
            TrackList(tracks:store.results)
            if store.results.isEmpty && !store.loading { empty }
        }
    }
    var empty:some View { ContentUnavailableView("No matches",systemImage:"magnifyingglass",description:Text("Try another title or artist.")) }
}
struct SearchSkeleton:View {
    @Environment(\.accessibilityReduceMotion) var reduced
    @State var shimmer=false
    var body:some View {
        VStack { ForEach(0..<3) { _ in HStack { RoundedRectangle(cornerRadius:8).frame(width:46,height:46); VStack(alignment:.leading) { Capsule().frame(width:155,height:9); Capsule().frame(width:90,height:7) }; Spacer() } } }
            .foregroundStyle(WaveStyle.card).overlay { if !reduced { GeometryReader { g in LinearGradient(colors:[.clear,.white.opacity(0.12),.clear],startPoint:.leading,endPoint:.trailing).frame(width:g.size.width/2).offset(x:shimmer ? g.size.width : -g.size.width/2) }.mask(Rectangle()).clipped() } }.accessibilityElement(children:.ignore).accessibilityLabel("Searching catalogs")
            .onAppear { if !reduced { withAnimation(.linear(duration:1.1).repeatForever(autoreverses:false)) { shimmer=true } } }
    }
}

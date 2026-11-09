import SwiftUI

struct DiscoveryShelves:View {
    let chart:[MusicTrack]
    @EnvironmentObject var shelf:Shelf
    var body:some View {
        let likes=shelf.tracks("liked"),history=shelf.tracks("history")
        let artists=Set((likes+history).map(\.artist))
        let genres=Set((likes+history).compactMap(\.genre))
        let heard=Set((likes+history).map(\.id))
        let matches=chart.filter { !heard.contains($0.id) && (artists.contains($0.artist) || $0.genre.map(genres.contains)==true) }
        if !matches.isEmpty {
            Text("Made For You").font(.title2.bold()); Text("Chart picks matching your saved artists and genres.").font(.caption).foregroundStyle(.secondary)
            TrackList(tracks:Array(matches.prefix(3)))
        }
        let pool=SearchEngine.rank((likes+history+matches).filter(\.canPlay),term:"")
        if pool.count>=3 {
            let day=Calendar.current.ordinality(of:.day,in:.era,for:Date()) ?? 0
            let offset=day % pool.count
            let mix=Array((Array(pool[offset...])+Array(pool[..<offset])).prefix(12))
            NavigationLink { ScrollView { LazyVStack(spacing:12) { TrackList(tracks:mix) }.padding() }.navigationTitle("Daily Mix") } label:{
                HStack { Image(systemName:"shuffle").font(.title); VStack(alignment:.leading) { Text("Daily Mix").font(.headline); Text("From your listening and favorites").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName:"chevron.right") }.padding().background(WaveStyle.card,in:RoundedRectangle(cornerRadius:16))
            }.buttonStyle(.plain)
        }
        if !chart.isEmpty {
            let artists=chart.reduce(into:[MusicTrack]()) { list,t in if !list.contains(where:{ $0.artist==t.artist }) { list.append(t) } }
            Text("Artists on the Chart").font(.title2.bold())
            ScrollView(.horizontal) { HStack(spacing:15) { ForEach(artists.prefix(8)) { t in
                NavigationLink { DetailScreen(seed:t,album:false,candidates:chart) } label:{ VStack { if let url=t.artistImage { AsyncImage(url:url) { phase in if let image=phase.image { image.resizable().scaledToFill() } else { Color(white:0.1) } }.frame(width:72,height:72).clipShape(Circle()) } else { Image(systemName:"person.crop.circle").font(.largeTitle).frame(width:72,height:72) }; Text(t.artist).font(.caption).lineLimit(1) }.frame(width:86) }.buttonStyle(.plain)
            } } }.scrollIndicators(.hidden)
            let recent=chart.filter { t in
                guard let s=t.released,let date=ISO8601DateFormatter().date(from:s) else { return false }
                return (0...(30.0*86400)).contains(Date().timeIntervalSince(date))
            }
            if !recent.isEmpty { Text("New Releases").font(.title2.bold()); TrackList(tracks:Array(recent.prefix(3))) }
            let buckets=Dictionary(grouping:chart.filter { $0.genre != nil },by:{ $0.genre ?? "" })
            if !buckets.isEmpty {
                Text("Genres on the Chart").font(.title2.bold())
                LazyVGrid(columns:[GridItem(.adaptive(minimum:125))],alignment:.leading) { ForEach(buckets.keys.sorted(),id:\.self) { genre in
                    NavigationLink { ScrollView { LazyVStack { TrackList(tracks:buckets[genre] ?? []) }.padding() }.navigationTitle(genre) } label:{ Text(genre).font(.subheadline.bold()).frame(maxWidth:.infinity,minHeight:45).background(WaveStyle.surface,in:RoundedRectangle(cornerRadius:12)) }
                } }
            }
        }
        let albums=(likes+history).filter { $0.album != nil }.reduce(into:[MusicTrack]()) { out,t in
            if !out.contains(where:{ $0.album==t.album && $0.artist==t.artist }) { out.append(t) }
        }
        if !albums.isEmpty { Text("Albums to Revisit").font(.title2.bold()); ForEach(albums.prefix(4)) { t in NavigationLink { DetailScreen(seed:t,album:true) } label:{ Label(t.album ?? t.title,systemImage:"opticaldisc").frame(minHeight:44) } } }
    }
}

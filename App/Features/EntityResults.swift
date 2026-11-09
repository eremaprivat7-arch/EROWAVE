import SwiftUI

struct EntityResults: View {
    let query:String
    let album:Bool
    @State private var rows=[CatalogEntity]()
    @State private var failures=[String]()
    @State private var loading=true
    var body:some View {
        Group {
            if loading { ProgressView("Searching "+(album ? "albums":"artists")) }
            ForEach(rows) { row in
                NavigationLink {
                    DetailScreen(seed:row.seed,album:album,entity:row)
                } label:{
                    HStack {
                        Image(systemName:album ? "opticaldisc":"person.crop.circle").font(.title2).frame(width:44)
                        VStack(alignment:.leading) { Text(row.title).font(.headline); Text([row.subtitle,row.source].filter { !$0.isEmpty }.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Image(systemName:"chevron.right").font(.caption)
                    }.padding(.vertical,5)
                }.buttonStyle(.plain)
            }
            if !failures.isEmpty { Text("Unavailable · "+failures.sorted().joined(separator:", ")).font(.caption).foregroundStyle(.secondary) }
            if rows.isEmpty && !loading { ContentUnavailableView("No catalog matches",systemImage:"magnifyingglass") }
        }.task(id:query+"|"+String(album)) {
            rows=[]; failures=[]; loading=true
            do {
                try await Task.sleep(for:.milliseconds(300))
                await withTaskGroup(of:(String,[CatalogEntity]?).self) { group in
                    let q=query, a=album
                    group.addTask { ("iTunes",try? await EntityCatalog.store(q,album:a)) }
                    group.addTask { ("MusicBrainz",try? await EntityCatalog.brainz(q,album:a)) }
                    for await (source,items) in group {
                        guard !Task.isCancelled else { return }
                        if let items { rows += items } else { failures.append(source) }
                    }
                }
                try Task.checkCancellation(); loading=false
            } catch {}
        }
    }
}

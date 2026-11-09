import SwiftData
import SwiftUI

@Model final class CollectionRecord {
    @Attribute(.unique) var key: String
    var title: String
    var kind: String
    var created: Date
    var contents: Data
    init(key: String, title: String, kind: String) {
        self.key=key; self.title=title; self.kind=kind; created=Date(); contents=Data("[]".utf8)
    }
    var tracks: [MusicTrack] { (try? JSONDecoder().decode([MusicTrack].self,from:contents)) ?? [] }
}
@MainActor final class Shelf: ObservableObject {
    let context: ModelContext
    @Published private(set) var records: [CollectionRecord] = []
    @Published var error: String?
    init(_ context: ModelContext) {
        self.context=context
        do {
            records = try context.fetch(FetchDescriptor<CollectionRecord>(sortBy:[SortDescriptor(\.created)]))
            if let data=UserDefaults.standard.data(forKey:"favorites") {
                let old=try JSONDecoder().decode([MusicTrack].self,from:data).map { item in
                    var track=item
                    if track.source=="iTunes" { track.previewURL=nil; track.artworkURL=nil }
                    return track
                }
                if get("liked")==nil {
                    let record=CollectionRecord(key:"liked",title:"Liked Songs",kind:"system")
                    record.contents=try JSONEncoder().encode(old); context.insert(record); try context.save(); records.append(record)
                }
                UserDefaults.standard.removeObject(forKey:"favorites")
            }
        } catch { self.error=error.localizedDescription }
    }
    func get(_ key:String) -> CollectionRecord? { records.first { $0.key==key } }
    func tracks(_ key:String) -> [MusicTrack] { get(key)?.tracks ?? [] }
    func has(_ key:String,_ t:MusicTrack) -> Bool { tracks(key).contains { $0.id==t.id } }
    func save(_ key:String,_ title:String,_ kind:String,_ tracks:[MusicTrack]) {
        let existing=get(key)
        let record=existing ?? CollectionRecord(key:key,title:title,kind:kind)
        do {
            let data=try JSONEncoder().encode(tracks)
            if existing==nil { context.insert(record) }
            record.title=title; record.contents=data
            try context.save()
            if existing==nil { records.append(record) } else { objectWillChange.send() }
        } catch { context.rollback(); self.error=error.localizedDescription }
    }
    func toggle(_ key:String,_ title:String,_ kind:String,_ t:MusicTrack) {
        let items=tracks(key)
        save(key,title,kind,items.contains { $0.id==t.id } ? items.filter { $0.id != t.id } : [t]+items)
    }
    func add(_ t:MusicTrack,to list:CollectionRecord) {
        guard !has(list.key,t) else { return }
        save(list.key,list.title,list.kind,list.tracks+[t])
    }
    func heard(_ t:MusicTrack) {
        let key = "events"
        save(key,"Listening History","system",Array(([t]+tracks(key)).prefix(300)))
        save("history","Recently Played","system",Array(([t]+tracks("history").filter { $0.id != t.id }).prefix(200)))
    }
    func remove(_ list:CollectionRecord) {
        context.delete(list)
        do { try context.save(); records.removeAll { $0 === list } }
        catch { context.rollback(); self.error=error.localizedDescription }
    }
}

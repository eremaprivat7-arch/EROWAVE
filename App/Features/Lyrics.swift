import SwiftUI
import UniformTypeIdentifiers

struct LyricLine:Identifiable,Equatable {
    let id:Int, time:Double, text:String
    static func parse(_ input:String)->[Self] {
        let pattern = #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        guard let re=try? NSRegularExpression(pattern:pattern) else { return [] }
        var lines=[Self]()
        for raw in input.components(separatedBy:.newlines) {
            let s=raw as NSString
            let matches=re.matches(in:raw,range:NSRange(location:0,length:s.length))
            guard let last=matches.last else { continue }
            let text=s.substring(from:NSMaxRange(last.range)).trimmed
            for m in matches {
                guard let min=Double(s.substring(with:m.range(at:1))),let sec=Double(s.substring(with:m.range(at:2))),sec<60 else { continue }
                let fraction=m.range(at:3).location==NSNotFound ? 0 : Double("0."+s.substring(with:m.range(at:3))) ?? 0
                lines.append(Self(id:lines.count,time:min*60+sec+fraction,text:text))
            }
        }
        return lines.sorted { $0.time == $1.time ? $0.id<$1.id:$0.time<$1.time }
    }
}
struct LyricsScreen:View {
    let track:MusicTrack
    @EnvironmentObject var player:PlayerStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) var reduced
    @State var lines=[LyricLine]()
    @State var importFile=false
    @State var follow=true
    @State var error:String?
    var file:URL {
        let name=Data(track.id.utf8).base64EncodedString().replacingOccurrences(of:"/",with:"_")
        return URL.documentsDirectory.appending(path:"lyrics").appending(path:name+".lrc")
    }
    var current:Int? { lines.last { $0.time<=player.progress }?.id }
    var body:some View {
        NavigationStack {
            VStack {
                if lines.isEmpty { ContentUnavailableView(track.asset != nil ? "Instrumental recording":"Lyrics unavailable",systemImage:"quote.bubble",description:Text("You can import an LRC file you have permission to use.")) }
                else {
                    Toggle("Follow playback",isOn:$follow).padding(.horizontal)
                    ScrollViewReader { proxy in ScrollView {
                        LazyVStack(alignment:.leading,spacing:20) { ForEach(lines) { line in Button { player.seek(line.time) } label:{ Text(line.text).font(.title.bold()).foregroundStyle(current==line.id ? .white:.gray).frame(maxWidth:.infinity,alignment:.leading) }.id(line.id) } }.padding()
                    }.onChange(of:current,initial:true) { _,id in if follow,let id { withAnimation(reduced ? nil:.easeOut) { proxy.scrollTo(id,anchor:.center) } } } }
                }
                if let error { Text(error).font(.caption) }
                Button(lines.isEmpty ? "Import LRC":"Replace LRC",systemImage:"doc") { importFile=true }.buttonStyle(.bordered)
            }.navigationTitle("Lyrics").toolbar { Button("Done") { dismiss() } }
        }.task(id:track.id) { lines=(try? String(contentsOf:file,encoding:.utf8)).map(LyricLine.parse) ?? [] }
            .fileImporter(isPresented:$importFile,allowedContentTypes:[.plainText,UTType(filenameExtension:"lrc") ?? .data]) { result in
                do {
                    let url=try result.get(); let access=url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max)<512_000 else { throw CocoaError(.fileReadTooLarge) }
                    let text=try String(contentsOf:url,encoding:.utf8); let parsed=LyricLine.parse(text)
                    guard !parsed.isEmpty else { error="No timed lines found."; return }
                    try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
                    try text.write(to:file,atomically:true,encoding:.utf8); lines=parsed; error=nil
                } catch { self.error=error.localizedDescription }
            }
    }
}

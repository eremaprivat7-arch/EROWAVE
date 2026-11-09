import SwiftUI
import AVKit

struct MiniPlayer:View {
    let art:Namespace.ID
    @EnvironmentObject var player:PlayerStore
    var body:some View {
        if let t=player.track {
            VStack(spacing:4) {
                HStack {
                    Button { player.showFullPlayer=true } label:{
                        HStack { ArtworkView(track:t,size:44).matchedGeometryEffect(id:"art",in:art); VStack(alignment:.leading) { Text(t.title).font(.subheadline.bold()); Text(t.artist).font(.caption).foregroundStyle(.secondary) }; Spacer() }.lineLimit(1)
                    }.buttonStyle(.plain).accessibilityIdentifier("miniPlayer")
                    Button { player.toggle() } label:{ Image(systemName:player.isPlaying || player.buffering ? "pause.fill":"play.fill").frame(width:44,height:44) }.accessibilityLabel(player.isPlaying ? "Pause":"Play")
                }
                ProgressView(value:min(player.progress,max(1,player.duration)),total:max(1,player.duration)).tint(.white)
            }.padding(8).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:16)).padding(.horizontal,12)
        }
    }
}
private enum PlayerSheet:String,Identifiable { case queue,lyrics,playlist; var id:String { rawValue } }
struct FullPlayerScreen:View {
    let art:Namespace.ID
    @EnvironmentObject var player:PlayerStore
    @EnvironmentObject var shelf:Shelf
    @Environment(\.accessibilityReduceMotion) var reduced
    @State private var sheet:PlayerSheet?
    @GestureState var drag:CGFloat=0
    @State var scrub:Double?
    @State var tint=Color(white:0.12)
    var body:some View {
        GeometryReader { g in
            if let t=player.track {
                ZStack {
                    Color.black.ignoresSafeArea()
                    LinearGradient(colors:[tint.opacity(0.65),.black],startPoint:.top,endPoint:.bottom).ignoresSafeArea()
                    ScrollView {
                        VStack(spacing:18) {
                            HStack {
                                Button { player.showFullPlayer=false } label:{ Image(systemName:"chevron.down").frame(width:44,height:44) }.accessibilityLabel("Close player")
                                Spacer(); HStack { PlaybackIndicator(active:player.isPlaying); Kicker("Now playing") }; Spacer(); AirOutput().frame(width:44,height:44).accessibilityLabel("Audio output")
                            }.contentShape(Rectangle()).gesture(closeGesture)
                            ArtworkView(track:t,size:min(g.size.width-48,max(120,g.size.height*0.37))).matchedGeometryEffect(id:"art",in:art).gesture(closeGesture)
                            HStack {
                                VStack(alignment:.leading,spacing:4) { Kicker(t.source); Text(t.title).font(.title.bold()); Text([t.artist,t.album].compactMap { $0 }.joined(separator:" · ")).foregroundStyle(.secondary) }
                                Spacer(); Button { shelf.toggle("liked","Liked Songs","system",t) } label:{
                                    Image(systemName:shelf.has("liked",t) ? "heart.fill":"heart").font(.title2).symbolEffect(.bounce,value:shelf.has("liked",t)).frame(width:44,height:44)
                                }.accessibilityLabel(shelf.has("liked",t) ? "Unlike":"Like").sensoryFeedback(.selection,trigger:shelf.has("liked",t))
                            }
                            VStack {
                                Slider(value:Binding(get:{ min(scrub ?? player.progress,max(player.duration,1)) },set:{ scrub=$0 }),in:0...max(player.duration,1), onEditingChanged:{ editing in if !editing, let scrub { player.seek(scrub); self.scrub=nil } }).disabled(player.duration<=0).accessibilityLabel("Playback position")
                                HStack { Text(time(scrub ?? player.progress)); Spacer(); Text(time(player.duration)) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            HStack {
                                Button { player.state.shuffle.toggle() } label:{ Image(systemName:"shuffle").foregroundStyle(player.state.shuffle ? .white:.gray) }.accessibilityLabel(player.state.shuffle ? "Shuffle on":"Shuffle off")
                                Spacer(); Button { player.previous() } label:{ Image(systemName:"backward.end.fill").font(.title2) }.accessibilityLabel("Previous")
                                Spacer(); Button { player.toggle() } label:{
                                    ZStack { Circle().fill(.white); if player.buffering { ProgressView().tint(.black) } else { Image(systemName:player.isPlaying ? "pause.fill":"play.fill").font(.title).foregroundStyle(.black) } }.frame(width:66,height:66)
                                }.accessibilityLabel(player.isPlaying ? "Pause":"Play")
                                Spacer(); Button { player.next() } label:{ Image(systemName:"forward.end.fill").font(.title2) }.disabled(player.state.upcoming.isEmpty && player.state.loop != .all).accessibilityLabel("Next")
                                Spacer(); Button { switch player.state.loop { case .off:player.state.loop = .all; case .all:player.state.loop = .one; case .one:player.state.loop = .off } } label:{ Image(systemName:player.state.loop == .one ? "repeat.1":"repeat").foregroundStyle(player.state.loop == .off ? .gray:.white) }.accessibilityLabel("Repeat "+player.state.loop.rawValue)
                            }
                            if let error=player.error { Text(error).font(.caption); if let url=t.externalURL { Link("Open in "+t.source,destination:url) } }
                            HStack { Button("Lyrics",systemImage:"quote.bubble") { sheet = .lyrics }; Spacer(); Button("Playlist",systemImage:"text.badge.plus") { sheet = .playlist }; Spacer(); Button("Queue",systemImage:"list.bullet") { sheet = .queue }; Spacer(); if let url=t.externalURL { ShareLink(item:url) } else { ShareLink(item:t.title+" — "+t.artist) } }.font(.title3).labelStyle(.iconOnly).padding(.vertical)
                            if let url=t.externalURL { Link("Listen on "+t.source,destination:url).font(.caption) }
                        }.padding(.horizontal,24)
                    }.scrollIndicators(.hidden)
                }.task(id:t.id) { let color=await ArtworkTint.color(for:t); if !Task.isCancelled { withAnimation(reduced ? nil:.easeOut(duration:0.45)) { tint=color } } }
                .offset(y:max(0,drag)).sheet(item:$sheet) { which in switch which { case .queue:QueueScreen(); case .playlist:PlaylistPicker(track:t); case .lyrics:LyricsScreen(track:t) } }
            }
        }.accessibilityIdentifier("fullPlayer")
    }
    var closeGesture:some Gesture { DragGesture().updating($drag) { v,state,_ in state=max(0,v.translation.height) }.onEnded { if $0.predictedEndTranslation.height>95 { player.showFullPlayer=false } } }
    func time(_ s:Double)->String { let v=Int(max(0,s)); return String(format:"%d:%02d",v/60,v%60) }
}
struct AirOutput:UIViewRepresentable {
    func makeUIView(context:Context)->AVRoutePickerView { let view=AVRoutePickerView(); view.tintColor = .white; return view }
    func updateUIView(_ uiView:AVRoutePickerView,context:Context) {}
}
struct QueueScreen:View {
    @EnvironmentObject var player:PlayerStore
    @Environment(\.dismiss) var dismiss
    var body:some View {
        NavigationStack { List {
            if let t=player.track { Section("Playing now") { Text(t.title); Text(t.artist).foregroundStyle(.secondary) } }
            Section("Up next") {
                ForEach(Array(player.state.upcoming.enumerated()),id:\.offset) { _,t in VStack(alignment:.leading) { Text(t.title); Text(t.artist).font(.caption).foregroundStyle(.secondary) } }
                    .onMove { from,to in player.state.upcoming.move(fromOffsets:from,toOffset:to) }.onDelete { player.state.upcoming.remove(atOffsets:$0) }
                if player.state.upcoming.isEmpty { Text("The queue is empty.").foregroundStyle(.secondary) }
            }
            if !player.state.upcoming.isEmpty { Button("Shuffle queue") { player.state.upcoming.shuffle() }; Button("Clear queue",role:.destructive) { player.state.upcoming.removeAll() } }
        }.navigationTitle("Queue").toolbar { EditButton(); Button("Done") { dismiss() } } }
    }
}

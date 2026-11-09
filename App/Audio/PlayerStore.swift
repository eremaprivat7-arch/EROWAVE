import AVFoundation
import MediaPlayer
import SwiftUI

enum LoopMode: String, Codable, CaseIterable { case off, all, one }
struct SessionSnapshot: Codable {
    var current: MusicTrack?
    var upcoming: [MusicTrack] = []
    var previous: [MusicTrack] = []
    var position: Double = 0
    var loop: LoopMode = .off
    var shuffle = false

    mutating func advance(ended: Bool, choice: (Range<Int>) -> Int = { Int.random(in:$0) }) -> MusicTrack? {
        if ended && loop == .one { return current }
        if upcoming.isEmpty && loop == .all { upcoming=previous + [current].compactMap { $0 }; previous=[]; current=nil }
        guard !upcoming.isEmpty else { return nil }
        if let current { previous.append(current); previous=Array(previous.suffix(200)) }
        current=upcoming.remove(at:shuffle ? choice(upcoming.indices) : 0); position=0
        return current
    }
}
@MainActor final class PlayerStore: ObservableObject {
    @Published var state=SessionSnapshot() { didSet { persist() } }
    @Published var isPlaying=false
    @Published var buffering=false
    @Published var progress=0.0
    @Published var duration=0.0
    @Published var showFullPlayer=false
    @Published var error: String?
    var onHeard: ((MusicTrack)->Void)?
    var track: MusicTrack? { state.current }
    private let engine=AVPlayer()
    private var status:NSKeyValueObservation?
    private var playStatus:NSKeyValueObservation?
    private var timeObserver:Any?
    private var end:NSObjectProtocol?
    private var failure:NSObjectProtocol?
    private var notifications=[NSObjectProtocol]()
    private var resumeAfterInterruption=false
    private var heardID:String?
    init() {
        if let data=UserDefaults.standard.data(forKey:"playback.v1"),let prior=try? JSONDecoder().decode(SessionSnapshot.self,from:data) { state=prior }
        let nc=NotificationCenter.default
        playStatus=self.engine.observe(\.timeControlStatus,options:[.new]) { [weak self] _,_ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying=self.engine.timeControlStatus == .playing
                self.buffering=self.engine.timeControlStatus == .waitingToPlayAtSpecifiedRate
                if self.isPlaying,let track=self.track,self.heardID != track.id { self.heardID=track.id; self.onHeard?(track) }
                self.nowPlaying()
            }
        }
        timeObserver=self.engine.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.4,preferredTimescale:600),queue:.main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let seconds=self.engine.currentTime().seconds
                if seconds.isFinite { self.progress=max(0,seconds) }
                let length=self.engine.currentItem?.duration.seconds ?? 0
                if length.isFinite { self.duration=max(0,length) }
            }
        }
        notifications.append(nc.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) { [weak self] note in
            let type=note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let flags=note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in
                guard let self else { return }
                if type==AVAudioSession.InterruptionType.began.rawValue { self.resumeAfterInterruption=self.isPlaying || self.buffering; self.pause() }
                else if type==AVAudioSession.InterruptionType.ended.rawValue { if self.resumeAfterInterruption && AVAudioSession.InterruptionOptions(rawValue:flags).contains(.shouldResume) { self.start() }; self.resumeAfterInterruption=false }
            }
        })
        notifications.append(nc.addObserver(forName:AVAudioSession.routeChangeNotification,object:nil,queue:.main) { [weak self] note in
            guard note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor in self?.resumeAfterInterruption=false; self?.pause() }
        })
        commands()
        if let track { load(track,at:state.position,autoplay:false) }
    }
    func play(_ selected:MusicTrack,following:[MusicTrack]=[]) {
        guard selected.canPlay else { return }
        state=SessionSnapshot(current:selected,upcoming:following.filter(\.canPlay),loop:state.loop,shuffle:state.shuffle)
        load(selected,at:0,autoplay:true); showFullPlayer=true
    }
    func enqueue(_ t:MusicTrack,first:Bool=false) {
        guard t.canPlay else { return }
        if track==nil { state.current=t; load(t,at:0,autoplay:false) }
        else if first { state.upcoming.insert(t,at:0) } else { state.upcoming.append(t) }
    }
    private func load(_ t:MusicTrack,at pos:Double,autoplay:Bool) {
        let nc=NotificationCenter.default
        if let end { nc.removeObserver(end) }; if let failure { nc.removeObserver(failure) }
        status=nil; engine.pause(); engine.replaceCurrentItem(with:nil); progress=0; duration=0; heardID=nil; error=nil
        guard let url=t.playableURL else { error="Audio is unavailable for this recording."; return }
        let wifiOnly=UserDefaults.standard.bool(forKey:"wifiOnly")
        let media=AVURLAsset(url:url,options:[AVURLAssetAllowsCellularAccessKey:!wifiOnly])
        let item=AVPlayerItem(asset:media)
        engine.replaceCurrentItem(with:item)
        end=nc.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:item,queue:.main) { [weak self,weak item] _ in
            Task { @MainActor in guard let self, let item, self.engine.currentItem === item else { return }; self.next(ended:true) }
        }
        failure=nc.addObserver(forName:.AVPlayerItemFailedToPlayToEndTime,object:item,queue:.main) { [weak self,weak item] _ in
            Task { @MainActor in guard let self,let item,self.engine.currentItem === item else { return }; self.error="Playback was interrupted. Try again or open the source."; self.pause() }
        }
        status=item.observe(\.status,options:[.initial,.new]) { [weak self] item,_ in
            Task { @MainActor in guard let self, self.engine.currentItem === item, item.status == .failed else { return }; self.error=item.error?.localizedDescription ?? "Audio unavailable."; self.pause() }
        }
        if pos>0 { seek(pos) }
        if autoplay { start() }; nowPlaying()
    }
    func start() {
        guard let item=engine.currentItem else { return }
        if item.status == .failed,let track { load(track,at:0,autoplay:true); return }
        do {
            let session=AVAudioSession.sharedInstance()
            try session.setCategory(.playback,mode:.default); try session.setActive(true)
            if duration>0 && progress>=duration-0.2 { seek(0) }
            engine.play()
        } catch { self.error=error.localizedDescription }
    }
    func pause() { engine.pause(); checkpoint() }
    func toggle() { if isPlaying || buffering { pause() } else { start() } }
    func seek(_ seconds:Double) {
        guard seconds.isFinite else { return }
        progress=max(0,seconds); engine.seek(to:CMTime(seconds:progress,preferredTimescale:600)); nowPlaying()
    }
    func next(ended:Bool=false) {
        if let next=state.advance(ended:ended) { load(next,at:0,autoplay:true) }
        else if ended { pause(); seek(0); checkpoint() }
    }
    func previous() {
        guard progress<3,let prior=state.previous.popLast() else { seek(0); return }
        if let track { state.upcoming.insert(track,at:0) }; state.current=prior; state.position=0; load(prior,at:0,autoplay:true)
    }
    func checkpoint() { state.position=progress }
    private func persist() { if let data=try? JSONEncoder().encode(state) { UserDefaults.standard.set(data,forKey:"playback.v1") } }
    private func nowPlaying() {
        guard let track else { return }
        var info:[String:Any]=[MPMediaItemPropertyTitle:track.title,MPMediaItemPropertyArtist:track.artist,MPNowPlayingInfoPropertyElapsedPlaybackTime:progress,MPNowPlayingInfoPropertyPlaybackRate:engine.rate]
        if duration>0 { info[MPMediaItemPropertyPlaybackDuration]=duration }; MPNowPlayingInfoCenter.default().nowPlayingInfo=info
    }
    private func commands() {
        let remote=MPRemoteCommandCenter.shared()
        remote.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.start() }; return .success }
        remote.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        remote.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        remote.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        remote.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e=event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let seconds=e.positionTime; Task { @MainActor in self?.seek(seconds) }; return .success
        }
    }
}

import SwiftUI

enum WaveStyle {
    static let bg = Color.black
    static let surface = Color(white: 0.071)
    static let card = Color(white: 0.086)
    static let muted = Color(white: 0.66)
}

struct ArtworkView: View {
    let track: MusicTrack
    var size: CGFloat = 56
    var body: some View {
        Group {
            if let n = track.asset, let image = UIImage(named: "cover\(n).jpg") {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                AsyncImage(url: track.artworkURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { ZStack { WaveStyle.card; Image(systemName: "waveform").foregroundStyle(WaveStyle.muted) } }
                }
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: min(22, size * 0.12))).accessibilityHidden(true)
    }
}
struct Kicker: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text.uppercased()).font(.caption2.monospaced().bold()).tracking(2).foregroundStyle(WaveStyle.muted) }
}

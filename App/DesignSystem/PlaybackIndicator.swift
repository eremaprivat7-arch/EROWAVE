import SwiftUI

struct PlaybackIndicator: View {
    let active:Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body:some View {
        TimelineView(.animation(minimumInterval:1/12,paused:!active || reduce)) { timeline in
            let t=timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment:.center,spacing:2) {
                ForEach(0..<3) { i in
                    Capsule().frame(width:2,height:active && !reduce ? CGFloat(4+10*abs(sin(t*4+Double(i)*1.8))) : CGFloat(5+i*3))
                }
            }.frame(width:12,height:17)
        }.accessibilityHidden(true)
    }
}

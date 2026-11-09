import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

actor ArtworkTint {
    private static let shared=ArtworkTint()
    private let context=CIContext(options:[.workingColorSpace:NSNull()])
    private var cache=[String:Color]()
    static func color(for t:MusicTrack) async -> Color { await shared.sample(t) }
    private func sample(_ t:MusicTrack) async -> Color {
        if let c=cache[t.id] { return c }
        guard let url=t.asset.flatMap({ Bundle.main.url(forResource:"cover\($0)",withExtension:"jpg") }) ?? t.artworkURL else { return Color(white:0.15) }
        do {
            let data:Data
            if url.isFileURL { data=try Data(contentsOf:url) } else { data=try await URLSession.shared.data(from:url).0 }
            try Task.checkCancellation()
            guard let input=CIImage(data:data) else { return .black }
            let avg=CIFilter.areaAverage(); avg.inputImage=input; avg.extent=input.extent
            guard let output=avg.outputImage else { return .black }
            var rgb=[UInt8](repeating:0,count:4)
            context.render(output,toBitmap:&rgb,rowBytes:4,bounds:CGRect(x:0,y:0,width:1,height:1),format:.RGBA8,colorSpace:CGColorSpaceCreateDeviceRGB())
            let color=Color(red:Double(rgb[0])/255,green:Double(rgb[1])/255,blue:Double(rgb[2])/255)
            if cache.count>50 { cache.removeAll() }; cache[t.id]=color; return color
        } catch { return Color(white:0.12) }
    }
}

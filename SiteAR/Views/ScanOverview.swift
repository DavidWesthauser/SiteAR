import SwiftUI
import simd

/// An isometric overview of actual detected plane boundaries, not a generated room model.
struct ScanOverview: View {
    let progress: ScanProgress
    var showCoverage = true
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                let polygons = progress.surfaces.map { $0.worldVertices.map { p in CGPoint(x: CGFloat(p.x-p.z)*0.7, y: CGFloat(p.x+p.z)*0.35-CGFloat(p.y)*0.8) } }
                let all = polygons.flatMap { $0 }
                guard let first = all.first else { return }
                let minX = all.map(\.x).min() ?? first.x, maxX = all.map(\.x).max() ?? first.x
                let minY = all.map(\.y).min() ?? first.y, maxY = all.map(\.y).max() ?? first.y
                let scale = min((size.width-12)/max(maxX-minX,0.1), (size.height-12)/max(maxY-minY,0.1))
                func project(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x-(minX+maxX)/2)*scale+size.width/2, y: (p.y-(minY+maxY)/2)*scale+size.height/2) }
                for polygon in polygons {
                    var path = Path(); path.addLines(polygon.map(project)); path.closeSubpath()
                    context.fill(path, with: .color(.white.opacity(0.22)))
                    context.stroke(path, with: .color(.white), lineWidth: 1.5)
                }
            }.frame(width:typeSize.isAccessibilitySize ? 100 : 150,height:typeSize.isAccessibilitySize ? 100 : 150).shadow(color:.black.opacity(0.7),radius:5).accessibilityHidden(true)
            VStack(spacing: 5) {
                Text("Live scan").font(.caption.bold())
                if showCoverage { Text("Blickrichtungen \(progress.coverage.headings.count)/4 · Standorte \(min(progress.coverage.positions.count,3))/3")
                    .font(.caption2).monospacedDigit().multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true) }
                Text("\(progress.verticalCount) vertikal · \(progress.horizontalCount) horizontal").font(.caption2).monospacedDigit().lineLimit(2).fixedSize(horizontal:false,vertical:true)

                if showCoverage {
                HStack(spacing: 6) {
                    ForEach(1...3, id: \.self) { step in
                        Capsule().fill(progress.stage >= step ? Color.mint : Color.white.opacity(0.3)).frame(height: 5)
                    }
                }
                Text(progress.canFinish ? "Raumkarte bereit" : (progress.normalTracking ? "Wände und Boden scannen" : "Finding Features…")).font(.caption2.bold()).fixedSize(horizontal:false,vertical:true)
                }
            }
        }.padding(12).frame(maxWidth:220).foregroundStyle(.white).background(.black.opacity(0.35),in:RoundedRectangle(cornerRadius:20))
    }
}

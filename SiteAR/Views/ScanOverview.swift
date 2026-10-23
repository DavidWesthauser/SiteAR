import SwiftUI
import simd

/// An isometric overview of actual detected plane boundaries, not a generated room model.
struct ScanOverview: View {
    let progress: ScanProgress
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(spacing: 12) {
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
                    context.fill(path, with: .color(.cyan.opacity(0.12)))
                    context.stroke(path, with: .color(.white), lineWidth: 1.5)
                }
            }.frame(width:typeSize.isAccessibilitySize ? 72 : 90,height:typeSize.isAccessibilitySize ? 72 : 90).background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text("Live scan").font(.subheadline.bold())
                Text("\(progress.verticalCount) vertikal · \(progress.horizontalCount) horizontal").font(.caption2).monospacedDigit().lineLimit(2)
                Text("\(progress.featureCount) Features").font(.caption2).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                HStack(spacing: 6) {
                    ForEach(1...3, id: \.self) { step in
                        Capsule().fill(progress.stage >= step ? Color.cyan : Color.secondary.opacity(0.3)).frame(height: 5)
                    }
                }
                Text(progress.canFinish ? "Raumkarte bereit" : (progress.normalTracking ? "Wände und Boden scannen" : "Finding Features…")).font(.caption2.bold()).fixedSize(horizontal:false,vertical:true)
            }
        }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

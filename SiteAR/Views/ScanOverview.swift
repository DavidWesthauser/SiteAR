import SwiftUI
import simd

/// An isometric overview of actual detected plane boundaries, not a generated room model.
struct ScanOverview: View {
    let progress: ScanProgress
    var showCoverage = true
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 8) {
            ScanMiniature(surfaces:progress.surfaces,yaw:progress.cameraYaw)
                .frame(width:typeSize.isAccessibilitySize ? 125 : 185,height:typeSize.isAccessibilitySize ? 110 : 170)
                .shadow(color:.black.opacity(0.35),radius:8,y:8)
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
        }.padding(12).frame(maxWidth:220).foregroundStyle(.white)
    }
}

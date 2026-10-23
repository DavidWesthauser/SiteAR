import SwiftUI
import simd

/// A shaded, animated projection of actual observed 3D patches, never a fabricated dollhouse.
struct ScanMiniature: View {
    let surfaces:[SurfacePatch]
    let yaw:Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entries:[UUID:Entry]=[:]
    @State private var shownYaw:Float=0
    @State private var yawFrom:Float=0
    @State private var yawStart=Date.distantPast
    struct Entry {
        var patch:SurfacePatch
        var from:[SIMD3<Float>]
        var start:Date
        var birth:Date
        func points(at date:Date,reduced:Bool) -> [SIMD3<Float>] {
            let target=patch.worldVertices
            guard from.count==target.count else { return target }
            let t=reduced ? Float(1) : min(1,max(0,Float(date.timeIntervalSince(start))/0.3))
            let eased=t*t*(3-2*t)
            return zip(from,target).map { $0+($1-$0)*eased }
        }
    }
    var body: some View {
        TimelineView(.animation(minimumInterval:1.0/30,paused:reduceMotion)) { tick in
            Canvas { context,size in
                let now=tick.date
                let t=reduceMotion ? Float(1) : min(1,max(0,Float(now.timeIntervalSince(yawStart))/0.35))
                let rotation=yawFrom+(shownYaw-yawFrom)*t
                let visible=surfaces.map { patch in entries[patch.id] ?? Entry(patch:patch,from:patch.worldVertices,start:.distantPast,birth:.distantPast) }
                    .sorted { $0.patch.id.uuidString<$1.patch.id.uuidString }
                struct Face { var points:[SIMD3<Float>]; var shade:Float; var alpha:Double }
                var faces:[Face]=[]
                for entry in visible {
                    let p=entry.points(at:now,reduced:reduceMotion)
                    let birth=reduceMotion ? 1 : min(1,max(0,now.timeIntervalSince(entry.birth)/0.55))
                    let center=p.reduce(SIMD3<Float>.zero,+)/Float(max(1,p.count))
                    let grown=p.map { center+($0-center)*Float(0.9+0.1*birth) }
                    faces += ScanVisualization.faces(entry.patch,vertices:grown).map { Face(points:$0.vertices,shade:$0.shade,alpha:birth) }
                }
                func rotated(_ p:SIMD3<Float>) -> SIMD3<Float> { ScanVisualization.rotate(p,yaw:rotation+0.7) }
                func projected(_ p:SIMD3<Float>) -> CGPoint { CGPoint(x:Double(p.x),y:Double(-p.y*0.85+p.z*0.5)) }
                let transformed=faces.map { Face(points:$0.points.map(rotated),shade:$0.shade,alpha:$0.alpha) }
                let all=transformed.flatMap(\.points).map(projected)
                guard let first=all.first else { return }
                let minX=all.map(\.x).min() ?? first.x,maxX=all.map(\.x).max() ?? first.x
                let minY=all.map(\.y).min() ?? first.y,maxY=all.map(\.y).max() ?? first.y
                let scale=min((size.width-24)/max(0.2,maxX-minX),(size.height-24)/max(0.2,maxY-minY))
                func fit(_ p:SIMD3<Float>) -> CGPoint { let q=projected(p);return CGPoint(x:(q.x-(minX+maxX)/2)*scale+size.width/2,y:(q.y-(minY+maxY)/2)*scale+size.height/2) }
                let sorted=transformed.sorted { a,b in
                    func depth(_ face:Face) -> Float { face.points.map { $0.z*0.85+$0.y*0.5 }.reduce(0,+)/Float(max(1,face.points.count)) }
                    return depth(a)<depth(b)
                }
                for face in sorted {
                    var path=Path(); path.addLines(face.points.map(fit));path.closeSubpath()
                    context.fill(path,with:.color(Color(white:Double(face.shade)).opacity(face.alpha)))
                    context.stroke(path,with:.color(.white.opacity(0.65*face.alpha)),lineWidth:0.7)
                }
            }
        }
        .onAppear { update(surfaces,animate:false); shownYaw = -yaw; yawFrom = -yaw }
        .onChange(of:surfaces) { _,value in update(value) }
        .onChange(of:yaw) { _,value in
            let now=Date(),t=min(1,max(0,Float(now.timeIntervalSince(yawStart))/0.35))
            yawFrom=yawFrom+(shownYaw-yawFrom)*t
            shownYaw=ScanVisualization.shortAngle(from:yawFrom,to:-value);yawStart=now
        }
        .accessibilityLabel("Live-Modell der erkannten Flächen")
    }
    private func update(_ surfaces:[SurfacePatch],animate:Bool=true) {
        let now=Date(), ids=Set(surfaces.map(\.id))
        entries=entries.filter { ids.contains($0.key) }
        for patch in surfaces {
            if let previous=entries[patch.id] {
                guard previous.patch != patch else { continue }
                entries[patch.id]=Entry(patch:patch,from:previous.points(at:now,reduced:reduceMotion),start:now,birth:previous.birth)
            } else { entries[patch.id]=Entry(patch:patch,from:patch.worldVertices,start:now,birth:animate ? now : .distantPast) }
        }
    }
}

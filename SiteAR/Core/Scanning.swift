import Foundation
import simd

/// A detected plane boundary, not a classified furniture model or proof of room coverage.
public struct SurfacePatch: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var pose: Pose
    public var vertices: [Point3]
    public var vertical: Bool
    public init(id: UUID, pose: Pose, vertices: [Point3], vertical: Bool) {
        self.id = id; self.pose = pose; self.vertices = vertices; self.vertical = vertical
    }
    public func validate() throws {
        guard vertices.count >= 3, vertices.count <= 2048,
              vertices.allSatisfy({ [$0.x,$0.y,$0.z].allSatisfy(\.isFinite) }) else { throw SpatialError.invalidGeometry }
    }
    public var worldVertices: [SIMD3<Float>] { vertices.map { (pose.matrix * SIMD4($0.vector,1)).xyz } }
}

/// Observable ARKit evidence, deliberately not a percentage of the physical room scanned.
public struct ScanProgress: Equatable, Sendable {
    public var normalTracking = false
    public var mapReady = false
    public var stableSeconds: Double = 0
    public var featureCount = 0
    public var surfaces: [SurfacePatch] = []
    public var coverage = ScanCoverage()
    public var cameraYaw:Float=0
    public var observedSurfaceCount=0
    public var renderingReduced=false
    public init() {}
    public var verticalCount: Int { surfaces.filter(\.vertical).count }
    public var horizontalCount: Int { surfaces.count - verticalCount }
    public var canFinish: Bool { normalTracking && mapReady && stableSeconds >= 2 && !surfaces.isEmpty && coverage.ready }
    public var stage: Int {
        guard normalTracking else { return 0 }
        if canFinish { return 3 }
        if !surfaces.isEmpty { return 2 }
        return normalTracking ? 1 : 0
    }
}

/// Movement evidence for a multi-view scan; not a guarantee of geometric or recognition coverage.
public struct ScanCoverage: Equatable, Sendable {
    public private(set) var headings: Set<Int> = []
    public private(set) var positions: [Point3] = []
    public init() {}
    public var ready: Bool { headings.count >= 4 && positions.count >= 3 }
    public mutating func observe(position: SIMD3<Float>, forward: SIMD3<Float>, reliable: Bool) {
        guard reliable, [position.x,position.y,position.z,forward.x,forward.y,forward.z].allSatisfy(\.isFinite),
              simd_length(SIMD2(forward.x,forward.z))>0.3 else { return }
        // Four world-relative compass sectors. A boundary crossing alone cannot fill all sectors.
        let angle=atan2(forward.x,forward.z)+Float.pi
        headings.insert(min(3,Int(angle/(Float.pi/2))))
        let horizontal=SIMD2(position.x,position.z)
        if positions.count<32 && positions.allSatisfy({ simd_distance(SIMD2($0.x,$0.z),horizontal)>=0.5 }) {
            positions.append(Point3(position))
        }
    }
    public var instruction: String {
        if positions.count<3 { return "Walk slowly to more positions in the room, looking at corners and textured surfaces." }
        if headings.count<4 { return "Look in the remaining directions. Capture each side of the room from overlapping viewpoints." }
        return "Look back at captured details as you return, so the room map connects."
    }
}

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
    public init() {}
    public var verticalCount: Int { surfaces.filter(\.vertical).count }
    public var horizontalCount: Int { surfaces.count - verticalCount }
    public var canFinish: Bool { normalTracking && mapReady && stableSeconds >= 2 && !surfaces.isEmpty }
    public var stage: Int {
        guard normalTracking else { return 0 }
        if canFinish { return 3 }
        if !surfaces.isEmpty { return 2 }
        return normalTracking ? 1 : 0
    }
}

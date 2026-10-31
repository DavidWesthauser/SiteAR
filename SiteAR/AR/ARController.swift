import ARKit
import RealityKit
import SwiftUI
import AVFoundation
import simd

struct FrozenDrawingFrame {
    let image: UIImage
    let viewProjection: simd_float4x4
    let viewport: CGSize
    let sessionFromRoom: Pose
}

/// All session callbacks are delivered on the main queue. Views never invent spatial positions.
@MainActor final class ARController: NSObject, ObservableObject, @preconcurrency ARSessionDelegate {
    @Published var localization = Localization()
    @Published var guidance = "Preparing camera…"
    @Published var trackingNormal = false
    @Published private(set) var trackingIssue:TrackingIssue = .initializing
    @Published private(set) var targetReady=false
    @Published private(set) var viewCapture=ViewCaptureRequest()
    var lockingView:Bool { viewCapture.isPending }
    @Published var mapped = false
    @Published var draft: [Point3] = []
    @Published private(set) var lineDraft=FreehandDraft()
    @Published private(set) var draftImage: UIImage?
    @Published var imageWidth: Float=0.4 { didSet { renderDraft() } }
    private(set) var imageData: Data?
    private var draftImageTexture: TextureResource?
    private var imageTextures: [String:TextureResource]=[:]
    var cachedImageTextureCount:Int { imageTextures.count }
    private var imageLoadGeneration = UUID()
    private var draftImageRequest = ViewCaptureRequest()
    @Published private(set) var loadingSavedImages = false
    @Published private(set) var imageLoading = false
    @Published var saveScanGuide = true
    private var lastDraftRender: CFTimeInterval=0
    var aimPoint: CGPoint?
    var imageHeight: Float { imageWidth*Float((draftImage?.size.height ?? 1)/(draftImage?.size.width ?? 1)) }
    @Published var draftText = "" { didSet { renderDraft() } }
    @Published private(set) var frozenFrame: FrozenDrawingFrame?
    @Published private(set) var drawingPlane: Pose? // roomFromDrawingPlane; immutable for this stroke.
    @Published var selected: Annotation?
    @Published var error: String?
    @Published var ready = false
    let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    private(set) var room: Room
    @Published private(set) var mode: ARMode
    @Published var scan = ScanProgress()
    @Published private(set) var surfaceTarget = "Find a surface"
    private var targetedSurface: UUID? { didSet { if oldValue != targetedSurface { refreshSurfaceColors() } } }
    @Published var tool: AnnotationKind = .line { didSet { renderDraft() } }
    @Published var showSurfaceGuides = true { didSet { refreshSurfaceVisuals() } }
    private var detectedSurfaces: [UUID: SurfacePatch] = [:]
    private var surfaceEntities: [UUID: AnchorEntity] = [:]
    private var surfaceStability:[UUID:SurfaceStability]=[:]
    private var placementStability:[UUID:SurfaceStability]=[:]
    private var placementTimes:[UUID:TimeInterval]=[:]
    private var renderedPatches:[UUID:SurfacePatch]=[:]
    private var outlineFade:AnimationResource?
    private var memoryObserver:NSObjectProtocol?
    @Published private(set) var renderingReduced=false
    var cachedSurfaceCount:Int { detectedSurfaces.count }
    private var lastProgressUpdate: TimeInterval = 0
    private var lastMiniatureUpdate: TimeInterval = 0
    private var coverage = ScanCoverage()
    var annotations: [Annotation] = []
    private var savedMap: ARWorldMap?
    private var normalSince: TimeInterval?
    private var startedAt = Date()
    private var content: AnchorEntity?
    private var preview: AnchorEntity?
    private struct RenderedContent {
        struct Key: Equatable { let annotations: [Annotation]; let textures: Set<String>; let alignment: Pose }
        let key: Key; let anchor: AnchorEntity
    }
    private var renderedContent: RenderedContent?
    private var stopped = false
    private var running = false
    private var restoredSentinel = false
    private var interrupted = false
    private var tapRecognizer: UITapGestureRecognizer?
    private var mapSave = MapSaveTransaction()

    init(room: Room, mode: ARMode) {
        self.room = room; self.mode = mode
        super.init()
        showSurfaceGuides = mode == .mapping
        // Overlays are flat unlit guides; skip camera post-processing and scene understanding the app never uses.
        view.renderOptions = [.disableMotionBlur,.disableDepthOfField,.disableCameraGrain,.disableHDR,.disableFaceMesh,.disablePersonOcclusion,.disableGroundingShadows]
        view.environment.sceneUnderstanding.options = []
        view.session.delegate = self; view.session.delegateQueue = .main
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        view.addGestureRecognizer(tap); tapRecognizer = tap
        view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragged(_:))))
        memoryObserver=NotificationCenter.default.addObserver(forName:UIApplication.didReceiveMemoryWarningNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.reduceScanLoad() }
        }
    }
    deinit { if let memoryObserver { NotificationCenter.default.removeObserver(memoryObserver) } }
    func reduceScanLoad() {
        guard !renderingReduced else { return };renderingReduced=true
        releaseSurfaceRendering()
    }
    func prepare(store: Store) async {
        do {
            guard ARWorldTrackingConfiguration.isSupported else { throw AppError.message("This device does not support AR world tracking. Use the task list instead.") }
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { throw AppError.message("Camera access is denied. Enable SiteAR in Settings → Privacy & Security → Camera. Tasks remain available without AR.") }
            try room.validate()
            if mode != .mapping {
                try await store.loadAnnotations(room)
                annotations = store.annotations.filter { $0.room_id == room.id }
                try annotations.forEach { try $0.validate(room: room) }
                if let path = room.map_path {
                    do {
                        let data = try await store.downloadAsset(path: path)
                        guard let map = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data),
                              map.anchors.contains(where: { $0.name == sentinelName }) else { throw AppError.message("Map is corrupt or belongs to another coordinate system.") }
                        savedMap = map
                    } catch { self.error = "Map unavailable: \(error.localizedDescription). Ask the manager to restore the saved room map; tasks remain available." }
                }
            }
            guard !stopped else { return }; ready = true
            if mode == .mapping { startMapping() }
            else if savedMap != nil { startMap() }
            else { localization.fail();guidance="No room map is available. Open the task list or ask the manager to rescan this room." }
            if mode != .mapping {
                await loadImageTextures(store:store)
                if !stopped { render() }
            }
        } catch { updateTracking(.unavailable);self.error = error.localizedDescription; guidance = "AR unavailable · use the task list" }
    }
    var mapAvailable:Bool { savedMap != nil }
    var canChangeScanGuide:Bool { mapSave.data == nil }
    private var sentinelName: String { "SiteAR.room.\(room.coordinate_id.uuidString)" }
    private func configuration(map: ARWorldMap? = nil) -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.isAutoFocusEnabled=true
        config.initialWorldMap = map
        // No depth stream or environment probes: nothing reads them, and both cost GPU time every frame.
        config.environmentTexturing = .none
        return config
    }
    private func reset(_ config: ARWorldTrackingConfiguration) {
        mapSave.reset()
        if mode == .mapping { savedMap = nil }
        cancelViewCapture();frozenFrame = nil
        clearVisuals(); localization.searching(); normalSince = nil; restoredSentinel = false
        clearSurfaces(); scan = ScanProgress(); coverage = ScanCoverage(); lastProgressUpdate = 0;lastMiniatureUpdate = 0;renderingReduced=false
        trackingNormal = false; trackingIssue = .initializing; targetReady=false; mapped = false
        startedAt = Date(); running = true; interrupted = false
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }
    func startMapping() {
        guard ready else { return }
        reset(configuration())
        view.session.add(anchor: ARAnchor(name: sentinelName, transform: matrix_identity_float4x4))
        guidance = "Move slowly around the room. Look at textured walls, floor and furniture."
    }
    func startMap() {
        guard ready, let savedMap else { error = "No usable room map. Ask the manager to restore it; the task list remains available."; return }
        reset(configuration(map: savedMap)); guidance = "Searching for the room. Look at captured details from overlapping viewpoints."
    }
    func continueSearching() {
        guard running, savedMap != nil, localization.state == .failed else { return }
        localization.searching(); normalSince=nil; startedAt=Date()
        guidance="Search continues. Move to a scanned area and look at familiar details."
    }
    func confirm() {
        localization.confirm(normalTracking: trackingNormal)
        if localization.state == .aligned { render(); renderDraft(); refreshSurfaceVisuals(); guidance = "Room recognized. Saved drawings are visible." }
    }
    func stop() { mapSave.reset();imageLoadGeneration=UUID();loadingSavedImages=false;cancelImageRequest();cancelViewCapture();stopped = true; running = false; view.session.pause(); clearVisuals(); clearSurfaces();imageTextures.removeAll();renderedContent=nil }
    func suspend() {
        mapSave.reset()
        updateTracking(.unavailable)
        guard running else { return }; interrupted = true; localization.lose(); trackingNormal = false; leaveFrozenView(); clearVisuals(); hideSurfaces(); view.session.pause()
        guidance = mode == .mapping ? "Scan paused. Return to continue scanning." : "Session paused. Return to the same spot to recover alignment."
    }
    /// Re-run without reset: ARKit keeps its in-memory map and anchors and relocalizes against them
    /// (see `sessionShouldAttemptRelocalization`). A full reset would throw away the scan in progress.
    func resume() {
        guard interrupted, ready, running, !stopped else { return }; interrupted = false
        view.session.run(configuration())
        normalSince = nil; startedAt = Date()
        if mode != .mapping { localization.searching() }
        guidance = mode == .mapping ? "Scan resumed. Point at an area you already scanned so tracking can reconnect." : TrackingIssue.relocalizing.instruction
    }
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard running, !stopped, !interrupted else { return }
        let issue:TrackingIssue
        switch frame.camera.trackingState {
        case .normal: issue = .none
        case .notAvailable: issue = .unavailable
        case .limited(let reason):
            switch reason {
            case .initializing: issue = .initializing
            case .excessiveMotion: issue = .excessiveMotion
            case .insufficientFeatures: issue = .insufficientFeatures
            case .relocalizing: issue = .relocalizing
            @unknown default: issue = .unavailable
            }
        }
        updateTracking(issue)
        let normal=issue == .none
        // Apple's guidance: a map is worth saving once status is .mapped or .extending, never .limited/.notAvailable.
        let mapIsReady=frame.worldMappingStatus == .mapped || frame.worldMappingStatus == .extending
        if mapped != mapIsReady { mapped=mapIsReady }
        if frame.timestamp - lastProgressUpdate > (renderingReduced ? 0.5 : 0.25) {
            if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical { reduceScanLoad() }
            lastProgressUpdate = frame.timestamp
            var progress = ScanProgress()
            progress.normalTracking = normal; progress.mapReady = mapped
            // Only threshold crossings matter to the UI. Quantizing keeps `scan` equal between ticks so SwiftUI stays idle.
            let stable = normal ? Double(frame.timestamp - (normalSince ?? frame.timestamp)) : 0
            progress.stableSeconds = min(2, (stable*2).rounded(.down)/2)
            progress.featureCount = min(frame.rawFeaturePoints?.points.count ?? 0, ScanProgress.minimumFeatureCount)
            let visible=ScanRenderingBudget.visiblePatches(Array(detectedSurfaces.values),camera:frame.camera.transform.columns.3.xyz,maximum:renderingReduced ? 12 : 24)
            // The miniature consolidates geometry on the main thread; refresh it once a second unless the set of patches changes.
            if frame.timestamp - lastMiniatureUpdate >= 1 || visible.map(\.id) != scan.surfaces.map(\.id) {
                progress.surfaces = visible; lastMiniatureUpdate = frame.timestamp
            } else { progress.surfaces = scan.surfaces }
            progress.observedSurfaceCount=detectedSurfaces.count
            progress.renderingReduced=renderingReduced
            if mode == .mapping {
                coverage.observe(position:frame.camera.transform.columns.3.xyz,forward:-frame.camera.transform.columns.2.xyz,
                                 reliable:normal && progress.hasUsefulFeatures && (frame.worldMappingStatus == .mapped || frame.worldMappingStatus == .extending),at:frame.timestamp)
            }
            let yaw=atan2(-frame.camera.transform.columns.2.x,-frame.camera.transform.columns.2.z)
            progress.cameraYaw=abs(ScanVisualization.shortAngle(from:scan.cameraYaw,to:yaw)-scan.cameraYaw)<0.035 ? scan.cameraYaw : yaw
            progress.coverage=coverage
            if scan != progress { scan = progress }
            updateTarget();renderScanSurfaces(visible:visible)
        }
        if normal { if normalSince == nil { normalSince = frame.timestamp } } else { normalSince = nil }
        if mode == .mapping {
            if !normal { setGuidance(issue.instruction) }
            else if !scan.hasUsefulFeatures { setGuidance("Look at a textured corner or door frame and pause briefly. More visible detail is needed for this view.") }
            else if !coverage.ready { setGuidance(coverage.instruction) }
            else if !mapped { setGuidance("Slowly revisit captured details so ARKit can connect the room map.") }
            else { setGuidance(scan.canFinish ? "Room map ready. Finish scanning to start drawing." : "Keep moving gently until surfaces are detected and tracking is stable.") }
            return
        }
        if !normal { setGuidance(issue.instruction) }
        // A locked view carries its own camera and alignment, so a tracking hiccup must not take it away mid-drawing.
        if !normal && frozenFrame == nil && localization.state == .aligned {
            localization.searching(); normalSince = nil; clearVisuals(); hideSurfaces(); startedAt = Date(); setGuidance(issue.instruction); return
        }
        if localization.recoverMap(restoredRoomAnchor: restoredSentinel, normalTracking: normal,
                                   stableSeconds: Double(frame.timestamp - (normalSince ?? frame.timestamp)),
                                   mapAvailable: frame.worldMappingStatus == .mapped || frame.worldMappingStatus == .extending) {
            render(); renderDraft(); refreshSurfaceVisuals()
            guidance = "Room recognized. Saved drawings are restored."
        }
        if localization.state == .relocalizing && Date().timeIntervalSince(startedAt) > 40 {
            localization.timedOut(); clearVisuals(); guidance = "Room not recognized yet. Look at captured corners and textured surfaces. Continue searching without a restart; drawings stay hidden."
        }
    }
    private func setGuidance(_ text:String) { if guidance != text { guidance=text } }
    func updateTracking(_ issue:TrackingIssue) {
        if trackingIssue != issue { trackingIssue=issue }
        let normal=issue == .none
        if trackingNormal != normal { trackingNormal=normal;if normal { refreshSurfaceVisuals() } else { hideSurfaces() } }
        if !normal {
            normalSince=nil;coverage.interrupt()
            if scan.normalTracking { scan.normalTracking=false;scan.stableSeconds=0;scan.coverage=coverage }
            surfaceStability.removeAll(keepingCapacity:true)
            placementStability.removeAll(keepingCapacity:true);placementTimes.removeAll(keepingCapacity:true)
            targetedSurface=nil
            cancelViewCapture();if targetReady { targetReady=false }
            if frozenFrame == nil, lineDraft.isDrawing { endStroke() }
        }
    }
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) { process(anchors) }
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) { process(anchors) }
    private func process(_ anchors: [ARAnchor]) {
        guard running, !interrupted, !stopped else { return }
        for anchor in anchors {
            if let plane = anchor as? ARPlaneAnchor { updateSurface(plane) }
            if anchor.name == sentinelName { restoredSentinel = true }

        }
    }
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors {
            removeSurface(id:anchor.identifier)
            if anchor.name == sentinelName {
                restoredSentinel=false
                if mode != .mapping {
                    localization.searching();normalSince=nil;startedAt=Date()
                    clearVisuals();hideSurfaces()
                    setGuidance("The saved room anchor was lost. Look at previously scanned details to recover alignment.")
                }
            }
        }
    }
    // Preserve the current origin during transient tracking loss. Recovery/restart stays explicit.
    func sessionShouldAttemptRelocalization(_ session:ARSession) -> Bool { running && !stopped }
    func sessionWasInterrupted(_ session: ARSession) { mapSave.reset();updateTracking(.relocalizing); interrupted = true; localization.lose(); trackingNormal = false; leaveFrozenView(); clearVisuals(); hideSurfaces(); guidance = "AR interrupted. Recover alignment after returning." }
    func sessionInterruptionEnded(_ session: ARSession) { resume() }
    func session(_ session: ARSession, didFailWithError error: Error) { mapSave.reset();updateTracking(.unavailable); localization.fail(); leaveFrozenView(); clearVisuals(); hideSurfaces(); self.error = "AR session failed: \(error.localizedDescription). Close AR and reopen the room." }

    private func hit(_ point: CGPoint) -> simd_float4x4? {
        guard trackingNormal else { return nil }
        guard let query = view.makeRaycastQuery(from: point, allowing: .existingPlaneGeometry, alignment: .any),
              let result = view.session.raycast(query).first,
              let frame = view.session.currentFrame,
              let plane=result.anchor as? ARPlaneAnchor,let pose=try? Pose(plane.transform),
              placementSurfaceIsReady(id:plane.identifier,pose:pose,at:frame.timestamp) else { return nil }
        let distance = simd_distance(frame.camera.transform.columns.3.xyz,result.worldTransform.columns.3.xyz)
        guard distance >= 0.15, distance <= 5 else { return nil }
        return result.worldTransform
    }
    private func updateTarget() {
        guard trackingNormal, let point=aimPoint,
              let query=view.makeRaycastQuery(from:point,allowing:.existingPlaneGeometry,alignment:.any),
              let result=view.session.raycast(query).first,
              let plane=result.anchor as? ARPlaneAnchor,
              let camera=view.session.currentFrame?.camera else {
            targetedSurface=nil; setTarget(ready:false,text:"Aim at a detected surface"); return
        }
        let distance=simd_distance(camera.transform.columns.3.xyz,result.worldTransform.columns.3.xyz)
        let settled=(try? Pose(plane.transform)).map { placementSurfaceIsReady(id:plane.identifier,pose:$0,at:view.session.currentFrame?.timestamp ?? 0) } ?? false
        let ready=settled && distance>=0.15 && distance<=5
        targetedSurface=ready ? plane.identifier : nil
        // A 5 cm readout avoids republishing the whole screen for millimetre jitter.
        setTarget(ready:ready,text:distance>5 ? "Move closer to the surface" : (distance<0.15 ? "Move slightly away from the surface" : (!settled ? "Surface refining — hold steady briefly" : String(format:"%@ · %.2f m",plane.alignment == .vertical ? "Vertical surface" : "Horizontal surface",(distance*20).rounded()/20))))
    }
    private func setTarget(ready:Bool,text:String) {
        if targetReady != ready { targetReady=ready }
        if surfaceTarget != text { surfaceTarget=text }
    }
    /// Placement tracking is independent of the display cache, including large/offscreen planes.
    func placementSurfaceIsReady(id:UUID,pose:Pose,at time:TimeInterval) -> Bool {
        if placementStability[id] == nil,placementStability.count>=4,
           let oldest=placementTimes.min(by:{$0.value<$1.value})?.key {
            placementStability.removeValue(forKey:oldest);placementTimes.removeValue(forKey:oldest)
        }
        var quality=placementStability[id] ?? surfaceStability[id] ?? SurfaceStability()
        quality.observe(pose,at:time);placementStability[id]=quality;placementTimes[id]=time
        return quality.isReady(at:time)
    }
    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: view)
        if mode != .mapping, localization.state == .aligned {
            var entity = view.entity(at: point)
            while let current = entity {
                if let id = UUID(uuidString: current.name), let item = annotations.first(where: { $0.id == id }) { selected = item; return }
                entity = current.parent
            }
            if mode == .editing && tool != .line { captureScreenPoint(point) }
        }
    }
    @objc private func dragged(_ recognizer: UIPanGestureRecognizer) {
        guard mode == .editing, [.line,.arrow].contains(tool) else { return }
        switch recognizer.state {
        case .began: beginStroke(); captureScreenPoint(recognizer.location(in:view),reportMiss:false)
        case .changed: captureScreenPoint(recognizer.location(in:view),reportMiss:false)
        case .ended: captureScreenPoint(recognizer.location(in:view),reportMiss:false); endStroke()
        case .cancelled,.failed: endStroke()
        default: break
        }
    }
    func beginStroke() { if !lockingView && tool == .line && !lineDraft.isDrawing { lineDraft.begin() } }
    func endStroke() {
        if tool == .line { lineDraft.end(); draft=lineDraft.points; renderDraft() }
    }
    func captureScreenPoint(_ point: CGPoint, reportMiss: Bool = true) {
        // On a locked view the snapshot's own projection and alignment are authoritative; live tracking is not needed.
        guard mode == .editing, !lockingView, trackingNormal || frozenFrame != nil,
              let alignment = frozenFrame?.sessionFromRoom ?? localization.roomToSession else { return }
        if drawingPlane == nil {
            guard let hit = hit(point), let frame = view.session.currentFrame else {
                if reportMiss { error = "No surface here yet. Scan another angle, or use measured-distance placement." }; return
            }
            lockPlane(point: hit.columns.3.xyz, normal: hit.columns.1.xyz, camera: frame.camera)
        }
        guard let drawingPlane, let camera = view.session.currentFrame?.camera else { return }
        let viewport = frozenFrame?.viewport ?? view.bounds.size
        guard viewport.width>0, viewport.height>0 else { return }
        let vp = frozenFrame?.viewProjection ?? camera.projectionMatrix(for: .portrait, viewportSize: viewport, zNear: 0.01, zFar: 100) * camera.viewMatrix(for: .portrait)
        let normalized = SIMD2<Float>(Float(point.x/viewport.width),Float(point.y/viewport.height))
        guard let ray = DrawingGeometry.ray(screen: normalized, inverseViewProjection: simd_inverse(vp)),
              let sessionPlane = try? Pose(alignment.matrix*drawingPlane.matrix),
              let position = DrawingGeometry.intersection(ray, plane: sessionPlane) else { return }
        appendPoint(Point3((simd_inverse(alignment.matrix)*SIMD4(position,1)).xyz))
    }
    private func lockPlane(point: SIMD3<Float>, normal: SIMD3<Float>, camera: ARCamera) {
        guard let alignment = localization.roomToSession else { return }
        let right = simd_inverse(camera.viewMatrix(for: .portrait)).columns.0.xyz
        guard let plane = try? DrawingGeometry.plane(at: point, normal: normal, camera: camera.transform.columns.3.xyz, preferredRight: right) else { return }
        drawingPlane = try? Pose(simd_inverse(alignment.matrix)*plane.matrix)
    }
    private func appendPoint(_ point: Point3) {
        switch tool {
        case .text,.marker,.image: draft = [point]
        case .arrow:
            if draft.isEmpty { draft = [point] }
            else if simd_distance(draft[0].vector, point.vector)>0.02 {
                if draft.count == 1 { draft.append(point) } else { draft = [draft[0],point] }
            }
        case .line:
            lineDraft.append(point); draft=lineDraft.points
        case .area:
            if let previous = draft.last, simd_distance(previous.vector,point.vector)<0.015 { return }
            guard draft.count<128 else { return }; draft.append(point)
        }
        renderDraft(throttled:tool == .line && lineDraft.isDrawing)
    }
    func freezeView() {
        if frozenFrame != nil { resumeCamera(); return }
        guard mode == .editing, !lockingView, trackingNormal, let alignment = localization.roomToSession, let frame = view.session.currentFrame else { return }
        guard draft.isEmpty else { error = "Save or clear this drawing before locking a new view."; return }
        let viewport = view.bounds.size
        guard let hit = hit(aimPoint ?? CGPoint(x:viewport.width/2,y:viewport.height/2)) else {
            error = "Aim at a detected wall or floor and hold steady briefly while it refines. Use measured-distance placement if no surface is detected."; return
        }
        guard let request=viewCapture.begin() else { return }
        lockPlane(point: hit.columns.3.xyz, normal: hit.columns.1.xyz, camera: frame.camera)
        let vp = frame.camera.projectionMatrix(for: .portrait, viewportSize: viewport, zNear: 0.01, zFar: 100)*frame.camera.viewMatrix(for: .portrait)
        view.snapshot(saveToHDR: false) { [weak self] image in
            Task { @MainActor in
                guard let self,self.viewCapture.accepts(request) else { return }
                defer { self.viewCapture.finish(request) }
                guard let image,self.trackingNormal,self.localization.state == .aligned,!self.stopped else {
                    if self.draft.isEmpty { self.drawingPlane=nil };return
                }
                guard self.draft.isEmpty else { return }
                guard let current=self.view.session.currentFrame,
                      let before=try? Pose(frame.camera.transform),let after=try? Pose(current.camera.transform),
                      CameraCaptureQuality.isSteady(from:before,to:after) else {
                    self.drawingPlane=nil;self.error="Hold the phone steady for a moment, then lock the view again.";return
                }
                self.frozenFrame = FrozenDrawingFrame(image: image, viewProjection: vp, viewport: viewport, sessionFromRoom: alignment)
                self.guidance = "View locked. Draw or type on this fixed surface, then resume the camera."
            }
        }
    }
    private func cancelViewCapture() {
        if viewCapture.isPending { viewCapture.cancel();if draft.isEmpty { drawingPlane=nil } }
    }
    func resumeCamera() {
        cancelViewCapture();frozenFrame = nil; if draft.isEmpty { drawingPlane = nil }
        // Tracking may have dropped while the view was locked; apply the deferred de-alignment now.
        if !trackingNormal, localization.state == .aligned { localization.searching(); normalSince=nil; startedAt=Date(); clearVisuals(); hideSurfaces(); guidance=trackingIssue.instruction }
    }
    /// Session-level loss (background, interruption, failure) still ends a locked view.
    private func leaveFrozenView() { if lineDraft.isDrawing { endStroke() }; cancelViewCapture(); frozenFrame = nil; if draft.isEmpty { drawingPlane = nil } }
    /// Capture at the centre crosshair; manual distance is an explicit adjustment, never a silent fallback.
    func capture(distance: Float? = nil) {
        guard !lockingView else { return }
        guard trackingNormal, let frame = view.session.currentFrame else { error = "Wait for normal tracking."; return }
        let point = aimPoint ?? CGPoint(x:view.bounds.midX,y:view.bounds.midY)
        if mode == .editing, distance == nil || drawingPlane != nil { captureScreenPoint(point); return }
        var matrix: simd_float4x4
        if let distance {
            let viewport=view.bounds.size
            guard viewport.width>0, viewport.height>0 else { return }
            let vp=frame.camera.projectionMatrix(for:.portrait,viewportSize:viewport,zNear:0.01,zFar:100)*frame.camera.viewMatrix(for:.portrait)
            guard let ray=DrawingGeometry.ray(screen:SIMD2(Float(point.x/viewport.width),Float(point.y/viewport.height)),inverseViewProjection:simd_inverse(vp)),
                  let position=DrawingGeometry.measuredPoint(camera:frame.camera.transform.columns.3.xyz,direction:ray.direction,distance:distance) else { return }
            matrix=frame.camera.transform; matrix.columns.3=SIMD4(position,1)
        } else {
            guard let hit = hit(point) else { error = "No surface found. Move slowly, try another angle, or choose explicit distance placement."; return }; matrix = hit
        }
        let position = Point3(matrix.columns.3.xyz)
        if mode == .mapping { return }
        guard mode == .editing, let alignment = localization.roomToSession else { error = "Confirm room alignment before placing instructions."; return }
        if drawingPlane == nil { lockPlane(point: position.vector, normal: frame.camera.transform.columns.2.xyz, camera: frame.camera) }
        let roomPoint = (simd_inverse(alignment.matrix) * SIMD4(position.vector,1)).xyz
        appendPoint(Point3(roomPoint))
    }
    func undoPoint() {
        guard !draft.isEmpty else { return }
        if tool == .line { lineDraft.undo(); draft=lineDraft.points } else { draft.removeLast() }
        if draft.isEmpty && frozenFrame == nil { drawingPlane=nil }; renderDraft()
    }
    func clearDraft() { lineDraft.clear(); draft = []; if frozenFrame == nil { drawingPlane = nil }; if let preview { view.scene.removeAnchor(preview) }; preview = nil }
    func makeAnnotation(kind: AnnotationKind, title: String, detail: String, priority: Int, image: SpatialImage? = nil) throws -> Annotation {
        guard localization.roomToSession != nil, let first = draft.first else { throw AppError.message("Capture a point after aligning the room.") }
        var matrix = drawingPlane?.matrix ?? matrix_identity_float4x4
        matrix.columns.3 = SIMD4(first.vector,1)
        let inverse = simd_inverse(matrix)
        let paths = kind == .line ? lineDraft.strokes.filter { $0.count>=2 }.map { $0.map { Point3((inverse*SIMD4($0.vector,1)).xyz) } } : []
        let points = kind == .line ? Array((paths.first ?? []).prefix(128)) : draft.map { Point3((inverse*SIMD4($0.vector,1)).xyz) }
        var result = Annotation(room: room, kind: kind, pose: try Pose(matrix), points: points, title: title, detail: detail)
        result.priority = priority; result.image=image
        if kind == .line { result.strokes=paths }
        do { try result.validate(room: room) }
        catch { throw AppError.message(kind == .area ? "Tap at least three corners on the same surface; the first three must not be on one straight line." : (kind == .image ? "Check the image, its size and position on the surface." : "Draw at least one stroke, then lift your finger.")) }
        return result
    }
    func reload(_ items: [Annotation], store: Store) async { guard !stopped else { return };annotations = items; await loadImageTextures(store:store); if !stopped { render() } }
    func beginImageRequest(clearExisting:Bool = false) -> UUID {
        draftImageRequest.cancel()
        let request=draftImageRequest.begin()!
        imageLoading=true
        if clearExisting { imageData=nil;draftImage=nil;draftImageTexture=nil;renderDraft() }
        return request
    }
    func imageRequestIsCurrent(_ request:UUID) -> Bool { !stopped && draftImageRequest.accepts(request) }
    func finishImageRequest(_ request:UUID) { if draftImageRequest.finish(request) { imageLoading=false } }
    func cancelImageRequest() { draftImageRequest.cancel();imageLoading=false }
    func setImage(_ data: Data,request:UUID? = nil) async throws {
        if let request, !imageRequestIsCurrent(request) { throw CancellationError() }
        let asset=try await SpatialImageAsset.prepare(data)
        guard !stopped,request.map(imageRequestIsCurrent) ?? true else { throw CancellationError() }
        imageData=asset.data; draftImage=asset.image; draftImageTexture=asset.texture
        imageWidth=min(0.4,3/Float(asset.image.size.height/asset.image.size.width)); renderDraft()
    }
    func restoreImageDraft(_ item: Annotation, store: Store, request:UUID) async throws {
        guard let image=item.image else { return }
        let data=try await store.downloadAsset(path:image.path)
        try await setImage(data,request:request)
        guard imageRequestIsCurrent(request) else { throw CancellationError() }
        imageWidth=image.width
    }
    private func loadImageTextures(store: Store) async {
        guard !stopped,!Task.isCancelled else { return }
        let generation=UUID();imageLoadGeneration=generation
        let validPaths=Set(annotations.compactMap { $0.image?.path })
        imageTextures=imageTextures.filter { validPaths.contains($0.key) }
        if localization.state == .aligned { render() }
        let missing=validPaths.filter { imageTextures[$0] == nil }.sorted()
        guard !missing.isEmpty,!stopped,!Task.isCancelled else { loadingSavedImages=false;return }
        loadingSavedImages=true
        defer { if imageLoadGeneration == generation { loadingSavedImages=false } }
        for path in missing {
            guard imageLoadGeneration == generation,!stopped,!Task.isCancelled else { return }
            do {
                let data=try await store.downloadAsset(path:path)
                guard imageLoadGeneration == generation,!stopped,!Task.isCancelled else { return }
                let texture=try await SpatialImageAsset.loadTexture(data)
                guard imageLoadGeneration == generation,!stopped,!Task.isCancelled else { return }
                imageTextures[path]=texture
            } catch {
                guard imageLoadGeneration == generation,!stopped,!Task.isCancelled else { return }
                self.error="A saved image could not be loaded. Its task remains available in the list. \(error.localizedDescription)"
            }
        }
    }
    func saveMap(store: Store) async throws -> Room {
        let generation = mapSave.generation
        guard mode == .mapping, running, !stopped, !interrupted, trackingNormal else {
            throw AppError.message("The scan is paused. Recover tracking before saving the room.")
        }
        if let publication = mapSave.publication {
            try await store.publishRoom(publication)
            return try finishMapPublication(publication,generation:generation)
        }
        guard scan.canFinish else {
            throw AppError.message("Pause at textured views in all four directions from at least three positions. Wait for stable tracking, detected surfaces and a ready room map.")
        }
        if mapSave.data == nil {
            let guide:String?
            if saveScanGuide {
                guard let buffer=view.session.currentFrame?.capturedImage,
                      let encoded=await ScanGuideImage.capture(buffer) else {
                    throw AppError.message("Couldn't capture the optional scan-view photo. Hold the camera steady and retry, or turn it off in Scan options.")
                }
                try mapSave.validate(generation)
                guide=encoded
            } else { guide=nil }
            let map: ARWorldMap = try await withCheckedThrowingContinuation { continuation in
                view.session.getCurrentWorldMap { map, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let map { continuation.resume(returning: map) }
                    else { continuation.resume(throwing: AppError.message("ARKit could not produce a map.")) }
                }
            }
            try mapSave.validate(generation)
            guard map.anchors.contains(where: { $0.name == sentinelName }) else { throw AppError.message("Room anchor missing from map. Restart mapping.") }
            let data = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
            try mapSave.capture(data, generation: generation, guide:guide)
            savedMap = map
        }
        guard trackingNormal, mapped, let data = mapSave.data else { throw AppError.message("Tracking changed while saving. Recheck the room and retry.") }
        let root = "\(room.project_id.uuidString.lowercased())/\(room.id.uuidString.lowercased())/\(UUID().uuidString.lowercased())"
        let mapPath = root + ".worldmap"
        var updated = room; updated.map_path = mapPath
        updated.scan_guide_jpeg = mapSave.guide
        updated.surfaces = detectedSurfaces.values.sorted { $0.id.uuidString < $1.id.uuidString }
        try await store.uploadAsset(path: mapPath, data: data, type: "application/octet-stream")
        try mapSave.validate(generation)
        // An interrupted/restarted session must never publish or reuse its predecessor's snapshot.
        try mapSave.stage(updated, generation: generation)
        try await store.publishRoom(updated)
        return try finishMapPublication(updated,generation:generation)
    }

    private func finishMapPublication(_ published:Room,generation:UUID) throws -> Room {
        do { try mapSave.validateCompletion(generation) }
        catch {
            // Persistence succeeded, but identity alignment belongs to the previous AR session.
            room=published;mode = .walkthrough;running=false;ready=false;savedMap=nil
            cancelViewCapture();view.session.pause();localization.lose();clearVisuals();clearSurfaces()
            guidance=error.localizedDescription
            throw error
        }
        return published
    }

    /// Continue drawing immediately in the same verified manager session, without relocalizing.
    func beginEditing(_ savedRoom: Room) {
        room = savedRoom; mode = .editing; showSurfaceGuides = false
        localization.propose(.identity, method: .map); localization.confirm(normalTracking: trackingNormal)
        render(); refreshSurfaceVisuals()
        guidance = "Draw on detected surfaces. Drag for a line, or tap corners for an area."
    }
    private func clearVisuals() {
        for anchor in [content, preview].compactMap({ $0 }) { view.scene.removeAnchor(anchor) }
        content = nil; preview = nil
    }
    private func dot(_ position: SIMD3<Float>, color: UIColor, radius: Float = 0.035) -> ModelEntity {
        let model = ModelEntity(mesh: .generateSphere(radius: radius), materials: [SimpleMaterial(color: color, isMetallic: false)])
        model.position = position; return model
    }
    private func label(_ text: String, at point: SIMD3<Float>, color: UIColor) -> ModelEntity {
        let mesh = MeshResource.generateText(String(text.prefix(240)), extrusionDepth: 0.001, font: .systemFont(ofSize: 0.045), containerFrame: CGRect(x: 0,y: 0,width: 0.7,height: 0.6), alignment: .left, lineBreakMode: .byWordWrapping)
        let model = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: color, isMetallic: false)])
        model.position = point + SIMD3(0.05,0.04,0); return model
    }
    private func renderDraft(throttled: Bool=false) {
        let now=CACurrentMediaTime()
        if throttled && now-lastDraftRender<1.0/30 { return }; lastDraftRender=now
        // Mid-stroke, finished strokes are unchanged: only re-mesh the stroke under the finger.
        if throttled, tool == .line, let preview, lineDraft.isDrawing, let live=lineDraft.strokes.last {
            preview.findEntity(named:"live")?.removeFromParent()
            addSmoothStroke(live,normal:drawingPlane?.matrix.columns.2.xyz ?? SIMD3(0,0,1),to:preview,color:.systemOrange,name:"live")
            return
        }
        if let preview { view.scene.removeAnchor(preview) }; preview=nil
        guard let alignment=localization.roomToSession, let first=draft.first else { return }
        let anchor=AnchorEntity(world:alignment.matrix)
        switch tool {
        case .line:
            for (index,path) in lineDraft.strokes.enumerated() where path.count>=2 {
                let live=lineDraft.isDrawing && index == lineDraft.strokes.count-1
                addSmoothStroke(path,normal:drawingPlane?.matrix.columns.2.xyz ?? SIMD3(0,0,1),to:anchor,color:.systemOrange,name:live ? "live" : "")
            }
        case .area:
            for (a,b) in zip(draft,draft.dropFirst()) { addSegment(a.vector,b.vector,to:anchor,color:.systemOrange) }
            if draft.count>=3,let last=draft.last { addSegment(last.vector,first.vector,to:anchor,color:.systemOrange) }
        case .image:
            if let texture=draftImageTexture {
                let root=Entity(); var pose=drawingPlane?.matrix ?? matrix_identity_float4x4; pose.columns.3=SIMD4(first.vector,1)
                root.transform=Transform(matrix:pose); addImage(texture,width:imageWidth,height:imageHeight,to:root); anchor.addChild(root)
            }
        case .arrow:
            if let last=draft.last,draft.count>=2 { addArrow(first.vector,last.vector,normal:drawingPlane?.matrix.columns.2.xyz ?? SIMD3(0,0,1),to:anchor,color:.systemOrange) }
        case .marker: anchor.addChild(dot(first.vector,color:.systemOrange,radius:0.025))
        case .text:
            let text=Entity(); var pose=drawingPlane?.matrix ?? matrix_identity_float4x4; pose.columns.3=SIMD4(first.vector,1)
            text.transform=Transform(matrix:pose); text.addChild(label(draftText.isEmpty ? "Text" : draftText,at:.zero,color:.systemOrange)); anchor.addChild(text)
        }
        preview=anchor; view.scene.addAnchor(anchor)
    }
    func render() {
        guard !stopped else { return }
        if let content { view.scene.removeAnchor(content) }; content = nil
        guard let alignment = localization.roomToSession, trackingNormal else { return }
        // Text meshes and collision shapes are expensive. Re-attach the last build when nothing changed,
        // so recovering tracking does not hitch at the moment drawings reappear.
        let key = RenderedContent.Key(annotations: annotations, textures: Set(imageTextures.keys), alignment: alignment)
        if let renderedContent, renderedContent.key == key {
            content = renderedContent.anchor; view.scene.addAnchor(renderedContent.anchor); return
        }
        let anchor = AnchorEntity(world: alignment.matrix)
        for item in annotations {
            let root = Entity(); root.name = item.id.uuidString; root.transform = Transform(matrix: item.pose.matrix)
            let color: UIColor = item.status == .completed ? .systemGreen : .systemCyan
            if item.kind == .marker { root.addChild(dot(.zero,color:color,radius:0.025)) }
            if item.kind == .text || !["Drawing","Zeichnung","Area marking","Fläche","Bild","Image"].contains(item.title) { root.addChild(label(item.title,at:.zero,color:color)) }
            let p = item.points.map(\.vector)
            if item.kind == .arrow, let first = p.first, let last = p.last, p.count>=2 {
                addArrow(first,last,normal:SIMD3(0,0,1),to:root,color:color)
            } else if item.kind == .image,let image=item.image,let texture=imageTextures[image.path] {
                addImage(texture,width:image.width,height:image.height,to:root)
            } else if item.kind == .line {
                for path in item.strokes ?? [item.points] { addSmoothStroke(path,normal:SIMD3(0,0,1),to:root,color:color) }
            } else if item.kind == .area,p.count>=2 {
                for (a,b) in zip(p,p.dropFirst()) { addSegment(a,b,to:root,color:color) }
                if item.kind == .area, let last = p.last, let first = p.first { addSegment(last,first,to:root,color:color) }
            }
            root.generateCollisionShapes(recursive: true); anchor.addChild(root)
        }
        content = anchor; view.scene.addAnchor(anchor); renderedContent = RenderedContent(key: key, anchor: anchor)
    }
    private func addSegment(_ a: SIMD3<Float>, _ b: SIMD3<Float>, to entity: Entity, color: UIColor, thickness: Float = 0.008) {
        let length = simd_distance(a,b); guard length > 0.002 else { return }
        let segment = ModelEntity(mesh: .generateBox(size: SIMD3(thickness,thickness,length)), materials: [UnlitMaterial(color: color)])
        segment.position = (a+b)/2; segment.orientation = simd_quatf(from: SIMD3(0,0,1), to: (b-a)/length); entity.addChild(segment)
    }
}

extension ARController {
    private func addSmoothStroke(_ controls:[Point3],normal:SIMD3<Float>,to entity:Entity,color:UIColor,name:String="") {
        let p=DrawingGeometry.smoothStroke(controls).map(\.vector)
        guard p.count>=2 else { return }
        let sides=8, radius:Float=0.0035
        var vertices:[SIMD3<Float>]=[],indices:[UInt32]=[]
        for i in p.indices {
            var tangent=p[min(i+1,p.count-1)]-p[max(i-1,0)]
            if simd_length(tangent)<0.00001 { tangent=i>0 ? p[i]-p[i-1] : p[1]-p[0] }
            guard simd_length(tangent)>0.00001 else { return }
            tangent=simd_normalize(tangent)
            var side=simd_cross(normal,tangent)
            if simd_length(side)<0.001 { side=simd_cross(abs(tangent.x)<0.9 ? SIMD3(1,0,0) : SIMD3(0,1,0),tangent) }
            side=simd_normalize(side); let up=simd_normalize(simd_cross(tangent,side))
            for j in 0..<sides { let a=Float(j)*2*Float.pi/Float(sides); vertices.append(p[i]+radius*(cos(a)*side+sin(a)*up)) }
        }
        for i in 0..<(p.count-1) { for j in 0..<sides {
            let a=UInt32(i*sides+j),b=UInt32(i*sides+(j+1)%sides),c=a+UInt32(sides),d=b+UInt32(sides)
            indices += [a,b,c,b,d,c]
        } }
        let start=UInt32(vertices.count); vertices.append(p[0]); let end=UInt32(vertices.count); vertices.append(p[p.count-1])
        for j in 0..<sides { indices += [start,UInt32((j+1)%sides),UInt32(j),end,UInt32((p.count-1)*sides+j),UInt32((p.count-1)*sides+(j+1)%sides)] }
        var descriptor=MeshDescriptor(name:"Smooth independent stroke"); descriptor.positions=MeshBuffers.Positions(vertices); descriptor.primitives = .triangles(indices)
        if let mesh=try? MeshResource.generate(from:[descriptor]) {
            let model=ModelEntity(mesh:mesh,materials:[UnlitMaterial(color:color)]); model.name=name; entity.addChild(model)
        }
    }
    private func addImage(_ texture:TextureResource,width:Float,height:Float,to entity:Entity) {
        var descriptor=MeshDescriptor(name:"Spatial image")
        descriptor.positions=MeshBuffers.Positions([SIMD3(-width/2,-height/2,0.002),SIMD3(width/2,-height/2,0.002),SIMD3(width/2,height/2,0.002),SIMD3(-width/2,height/2,0.002)])
        descriptor.textureCoordinates=MeshBuffers.TextureCoordinates([SIMD2(0,1),SIMD2(1,1),SIMD2(1,0),SIMD2(0,0)])
        descriptor.primitives = .triangles([0,1,2,0,2,3,0,2,1,0,3,2])
        var material=UnlitMaterial(); material.color = .init(tint:.white,texture:.init(texture)); material.blending = .transparent(opacity:.init(floatLiteral:1))
        if let mesh=try? MeshResource.generate(from:[descriptor]) { entity.addChild(ModelEntity(mesh:mesh,materials:[material])) }
    }
    private func updateSurface(_ plane: ARPlaneAnchor) {
        let boundary=ScanRenderingBudget.displayBoundary(plane.geometry.boundaryVertices.map(Point3.init),maximum:64)
        guard boundary.count>=3,let pose=try? Pose(plane.transform) else { removeSurface(id:plane.identifier);return }
        let patch=SurfacePatch(id:plane.identifier,pose:pose,vertices:boundary,vertical:plane.alignment == .vertical)
        updateSurfacePatch(patch)
        guard trackingNormal,detectedSurfaces[patch.id] != nil else { return }
        var stability=surfaceStability[patch.id] ?? SurfaceStability()
        stability.observe(pose,at:view.session.currentFrame?.timestamp ?? ProcessInfo.processInfo.systemUptime)
        surfaceStability[patch.id]=stability
    }
    private func removeSurface(id:UUID) {
        detectedSurfaces.removeValue(forKey:id);surfaceStability.removeValue(forKey:id)
        placementStability.removeValue(forKey:id);placementTimes.removeValue(forKey:id)
        renderedPatches.removeValue(forKey:id)
        if let root=surfaceEntities.removeValue(forKey:id) {
            root.isEnabled=false
            for child in Array(root.children) { child.removeFromParent() }
            view.scene.removeAnchor(root)
        }
        if targetedSurface == id { targetedSurface=nil;targetReady=false }
        if scan.surfaces.contains(where:{$0.id == id}) {
            scan.surfaces.removeAll(where:{$0.id == id});scan.observedSurfaceCount=detectedSurfaces.count
        }
    }
    /// Coalesce AR callbacks into a bounded metadata cache. Rendering occurs once per UI tick.
    func updateSurfacePatch(_ input:SurfacePatch) {
        var patch=input
        patch.vertices=ScanRenderingBudget.displayBoundary(input.vertices,maximum:64)
        guard patch.vertices.count>=3 else { removeSurface(id:patch.id);return }
        if detectedSurfaces[patch.id] == nil,detectedSurfaces.count>=128 {
            let camera=view.session.currentFrame?.camera.transform.columns.3.xyz ?? .zero
            func distance(_ item:SurfacePatch) -> Float { simd_distance_squared(item.pose.matrix.columns.3.xyz,camera) }
            guard let farthest=detectedSurfaces.values.max(by:{distance($0)<distance($1)}),distance(patch)<distance(farthest) else { return }
            detectedSurfaces.removeValue(forKey:farthest.id);surfaceStability.removeValue(forKey:farthest.id)
        }
        detectedSurfaces[patch.id]=patch
    }
    /// At most 24 patches and two drawables per patch; never one entity/animation per edge.
    /// `nearest` is the tick's already-ranked patch list, so ranking runs once per tick.
    func renderScanSurfaces(visible nearest:[SurfacePatch]? = nil) {
        guard trackingNormal,mode == .mapping || localization.state == .aligned else { hideSurfaces();return }
        let visible:[SurfacePatch]
        if showSurfaceGuides {
            let camera=view.session.currentFrame?.camera.transform.columns.3.xyz ?? .zero
            visible=nearest ?? ScanRenderingBudget.visiblePatches(Array(detectedSurfaces.values),camera:camera,maximum:renderingReduced ? 12 : 24)
        }
        else if mode == .editing,drawingPlane == nil,let id=targetedSurface,let patch=detectedSurfaces[id] { visible=[patch] }
        else { visible=[] }
        // ARKit refines most planes every frame. Rebuilding every outline each tick caused periodic main-thread
        // hitches, so new outlines always appear but refinements of existing ones are spread across ticks (nearest first).
        var refinements=renderingReduced ? 2 : 4
        let ids=Set(visible.map(\.id))
        for id in Array(surfaceEntities.keys) where !ids.contains(id) {
            if let root=surfaceEntities.removeValue(forKey:id) { view.scene.removeAnchor(root) }
            renderedPatches.removeValue(forKey:id)
        }
        for patch in visible {
            let root:AnchorEntity
            if let existing=surfaceEntities[patch.id] { root=existing }
            else {
                root=AnchorEntity(world:SIMD3<Float>.zero);surfaceEntities[patch.id]=root
                view.scene.addAnchor(root)
            }
            root.isEnabled=true;root.transform=Transform(matrix:patch.pose.matrix)
            let firstGeometry=renderedPatches[patch.id] == nil
            if let rendered=renderedPatches[patch.id] {
                if Self.outlineMatches(rendered.vertices,patch.vertices) { continue }
                guard refinements>0 else { continue }; refinements -= 1
            }
            let points=ScanRenderingBudget.displayBoundary(patch.vertices,maximum:renderingReduced ? 12 : 24)
                .map { Point3($0.vector+SIMD3<Float>(0,0.003,0)) }
            var allRendered=true
            for halo in (renderingReduced ? [false] : [true,false]) {
                let name=halo ? "halo" : "edge"
                guard let geometry=ScanRenderingBudget.outline(points,thickness:halo ? 0.013 : 0.0035) else {
                    root.findEntity(named:name)?.removeFromParent();allRendered=false;continue
                }
                var descriptor=MeshDescriptor(name:"Batched scan outline")
                descriptor.positions=MeshBuffers.Positions(geometry.positions);descriptor.primitives = .triangles(geometry.indices)
                guard let mesh=try? MeshResource.generate(from:[descriptor]) else {
                    root.findEntity(named:name)?.removeFromParent();allRendered=false;continue
                }
                if let model=root.findEntity(named:name) as? ModelEntity {
                    model.model=ModelComponent(mesh:mesh,materials:[outlineMaterial(halo:halo,selected:patch.id == targetedSurface)])
                } else {
                    let model=ModelEntity(mesh:mesh,materials:[outlineMaterial(halo:halo,selected:patch.id == targetedSurface)])
                    model.name=name;root.addChild(model)
                }
            }
            if allRendered {
                renderedPatches[patch.id]=patch
                if firstGeometry { revealOutline(root) }
            } else { renderedPatches.removeValue(forKey:patch.id) }
        }
    }
    /// Sub-centimetre boundary jitter is invisible at room scale and not worth a new mesh.
    private static func outlineMatches(_ a:[Point3],_ b:[Point3]) -> Bool {
        a.count == b.count && zip(a,b).allSatisfy { simd_distance_squared($0.vector,$1.vector) < 0.0001 }
    }
    /// One engine-managed animation per outline, without per-frame mesh regeneration.
    private func revealOutline(_ root:Entity) {
        guard !renderingReduced,!UIAccessibility.isReduceMotionEnabled else { return }
        if #available(iOS 18.0,*) {
            root.components.set(OpacityComponent(opacity:1))
            if outlineFade == nil {
                outlineFade=try? AnimationResource.generate(with:FromToByAnimation<Float>(from:0.15,to:1,duration:0.45,timing:.easeOut,bindTarget:.opacity,fillMode:.forwards))
            }
            if let outlineFade { root.playAnimation(outlineFade) }
        }
    }
    private func outlineMaterial(halo:Bool,selected:Bool) -> UnlitMaterial {
        var material=UnlitMaterial(color:selected ? .systemMint : .white)
        if halo { material.blending = .transparent(opacity:.init(floatLiteral:0.1)) }
        return material
    }
    private func addArrow(_ tail: SIMD3<Float>, _ tip: SIMD3<Float>, normal: SIMD3<Float>, to entity: Entity, color: UIColor) {
        let delta = tip-tail
        let normal = simd_length(simd_cross(normal,delta))<0.001 ? SIMD3<Float>(0,1,0) : normal
        guard let arrow = DrawingGeometry.arrow(tail:tail,tip:tip,normal:normal) else { return }
        let base = (arrow.left+arrow.right)/2
        addSegment(tail,base,to:entity,color:color,thickness:0.012)
        var descriptor = MeshDescriptor(name:"Arrowhead")
        descriptor.positions = MeshBuffers.Positions([arrow.tip,arrow.left,arrow.right])
        descriptor.primitives = .triangles([0,1,2,0,2,1])
        if let mesh = try? MeshResource.generate(from:[descriptor]) { entity.addChild(ModelEntity(mesh:mesh,materials:[UnlitMaterial(color:color)])) }
    }
    private func refreshSurfaceVisuals() {
        let allowed = trackingNormal && (mode == .mapping || localization.state == .aligned)
        for (id,entity) in surfaceEntities {
            entity.isEnabled = allowed && (showSurfaceGuides || (mode == .editing && drawingPlane == nil && id == targetedSurface))
        }
    }
    private func refreshSurfaceColors() {
        for (id,entity) in surfaceEntities {
            for child in entity.children {
                if let model=child as? ModelEntity { model.model?.materials=[outlineMaterial(halo:child.name.hasPrefix("halo"),selected:id == targetedSurface)] }
            }
        }
    }
    private func hideSurfaces() { for entity in surfaceEntities.values { entity.isEnabled = false } }
    private func releaseSurfaceRendering() {
        for entity in surfaceEntities.values { view.scene.removeAnchor(entity) }
        surfaceEntities=[:];renderedPatches=[:]
    }
    private func clearSurfaces() {
        releaseSurfaceRendering();detectedSurfaces=[:];surfaceStability=[:];placementStability=[:];placementTimes=[:]
    }
}

#if canImport(UIKit) && !canImport(SiteARCore)
import XCTest
import UIKit
import SwiftUI
import ARKit
import RealityKit
@testable import SiteAR

@MainActor final class ARLayoutTests: XCTestCase {
    private func sampleImage() -> UIImage {
        UIGraphicsImageRenderer(size:CGSize(width:160,height:100)).image { c in
            UIColor.systemBlue.setFill(); c.fill(CGRect(x:0,y:0,width:160,height:100))
            UIColor.systemYellow.setFill(); c.fill(CGRect(x:0,y:0,width:80,height:100))
        }
    }
    func testScreenStatesAtCompactSizesAndLargeText() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let store=Store(localURL:folder.appendingPathComponent("local.json"))
        let project=Project(owner_id:store.userID!,name:"Layout fixture")
        var room=Room(project_id:project.id,name:"Ein langer Raumname für die Layoutprüfung")
        room.map_path="test-only.worldmap"
        let patch=SurfacePatch(id:UUID(),pose:.identity,vertices:[Point3(.zero),Point3(SIMD3(2,0,0)),Point3(SIMD3(2,0,2))],vertical:false)
        let wallPose=try Pose(simd_float4x4(simd_quatf(angle:-Float.pi/2,axis:SIMD3(1,0,0))))
        let wall=SurfacePatch(id:UUID(),pose:wallPose,vertices:[Point3(.zero),Point3(SIMD3(2,0,0)),Point3(SIMD3(2,0,2.4)),Point3(SIMD3(0,0,2.4))],vertical:true)
        let sidePose=try Pose(simd_float4x4(simd_quatf(angle:Float.pi/2,axis:SIMD3(0,0,1))))
        let side=SurfacePatch(id:UUID(),pose:sidePose,vertices:[Point3(.zero),Point3(SIMD3(2.4,0,0)),Point3(SIMD3(2.4,0,2)),Point3(SIMD3(0,0,2))],vertical:true)
        var ready=ScanProgress(); ready.normalTracking=true; ready.mapReady=true; ready.stableSeconds=3; ready.featureCount=620; ready.surfaces=[patch,wall,side]

        for i in 0..<4 {
            let angle=Float(i)*Float.pi/2+0.2
            ready.coverage.observe(position:SIMD3(Float(i)*0.6,0,0),forward:SIMD3(sin(angle),0,cos(angle)),reliable:true)
        }
        let configurations:[(String,ARMode)] = [("scan-start",.mapping),("scan-ready",.mapping),("recognizing",.walkthrough),("tracking-lost",.editing),("draw-editor",.editing),("area-editor",.editing),("image-empty",.editing),("image-loaded",.editing),("worker-aligned",.walkthrough),("recovery",.walkthrough)]
        for (name,mode) in configurations {
            let ar=ARController(room:room,mode:mode)
            if name=="scan-ready" { ar.scan=ready; ar.trackingNormal=true; ar.mapped=true }
            if ["draw-editor","area-editor","image-empty","image-loaded","worker-aligned"].contains(name) {
                ar.trackingNormal=true; ar.localization.propose(.identity,method:.map); ar.confirm()
            }
            if name=="tracking-lost" { ar.localization.lose() }
            if name=="recognizing" { ar.localization.searching() }
            if name=="area-editor" { ar.tool = .area }
            if name.hasPrefix("image-") { ar.tool = .image }
            if name=="image-loaded" { try await ar.setImage(sampleImage().pngData()!) }
            if name=="recovery" { ar.localization.propose(.identity,method:.marker); ar.trackingNormal=true }
            for size in [CGSize(width:375,height:667),CGSize(width:375,height:812)] {
                try await snapshot(AnyView(ARScreen(controller:ar,manager:mode != .walkthrough)),store:store,name:"\(name)-\(Int(size.height))",size:size)
            }
            if ["draw-editor","image-loaded","scan-ready"].contains(name) {
                try await snapshot(AnyView(ARScreen(controller:ar,manager:true).environment(\.dynamicTypeSize,.accessibility1)),store:store,name:"\(name)-large-text",size:CGSize(width:375,height:667))
            }
            ar.stop()
        }
        let note=Annotation(room:room,kind:.line,pose:.identity,points:[Point3(.zero),Point3(SIMD3(1,0,0))],title:"Eine längere Arbeitsanweisung für die Wand",detail:"Mehrzeilige Beschreibung einer Aufgabe für den Techniker.")
        for manager in [true,false] {
            try await snapshot(AnyView(NavigationStack { TaskEditor(item:note,room:room,manager:manager) }),store:store,name:manager ? "task-manager" : "task-worker",size:CGSize(width:375,height:667))
        }
        try await snapshot(AnyView(DrawingWorkDetails(title:.constant("Eine längere Anweisung"),details:.constant("Mehrzeiliger Inhalt für die Prüfung."),priority:.constant(1))),store:store,name:"work-details-sheet",size:CGSize(width:375,height:667))
        try await snapshot(AnyView(DrawingPlacementSettings(measured:.constant(true),distance:.constant(1.5))),store:store,name:"placement-sheet",size:CGSize(width:375,height:667))
        try await snapshot(AnyView(AuthenticationView()),store:store,name:"login",size:CGSize(width:375,height:667))
        try await snapshot(AnyView(NavigationStack { SettingsView() }),store:store,name:"settings",size:CGSize(width:375,height:667))
        try await snapshot(AnyView(ProjectDashboard()),store:store,name:"empty-projects",size:CGSize(width:375,height:667))
    }
    func testMiniatureRendersWithoutAnAnimationClock() throws {
        let patch=SurfacePatch(id:UUID(),pose:.identity,vertices:[Point3(.zero),Point3(SIMD3(2,0,0)),Point3(SIMD3(2,0,2)),Point3(SIMD3(0,0,2))],vertical:false)
        let renderer=ImageRenderer(content:ScanMiniature(surfaces:[patch],yaw:0).frame(width:220,height:220).background(.black))
        renderer.scale=1
        let image=try XCTUnwrap(renderer.uiImage?.cgImage)
        let bytesPerRow=image.width*4
        var pixels=[UInt8](repeating:0,count:image.height*bytesPerRow)
        let count=pixels.withUnsafeMutableBytes { buffer -> Int in
            guard let context=CGContext(data:buffer.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:bytesPerRow,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
            context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
            let bytes=buffer.bindMemory(to:UInt8.self)
            return stride(from:0,to:bytes.count,by:4).filter { bytes[$0]>100 && bytes[$0+1]>100 && bytes[$0+2]>100 }.count
        }
        XCTAssertGreaterThan(count,1000,"Observed geometry must be visible before any animation tick")
    }
    func testSurfaceOutlineKeepsAnchorAcrossRefinements() async throws {
        let room=Room(project_id:UUID(),name:"Test-only scan renderer")
        let ar=ARController(room:room,mode:.mapping);ar.trackingNormal=true
        var patch=SurfacePatch(id:UUID(),pose:.identity,vertices:[Point3(.zero),Point3(SIMD3(1,0,0)),Point3(SIMD3(1,0,1)),Point3(SIMD3(0,0,1))],vertical:false)
        ar.updateSurfacePatch(patch)
        let root=try XCTUnwrap(ar.view.scene.anchors.first)
        XCTAssertEqual(root.children.count,8) // Four edges and subtle halos; no filled camera faces.
        ar.updateSurfacePatch(patch)
        XCTAssertTrue(root === ar.view.scene.anchors.first)
        try await Task.sleep(for:.milliseconds(720))
        patch.vertices[1]=Point3(SIMD3(2,0,0));patch.vertices[2]=Point3(SIMD3(2,0,1))
        ar.updateSurfacePatch(patch)
        XCTAssertEqual(ar.view.scene.anchors.count,1)
        XCTAssertTrue(root === ar.view.scene.anchors.first)
        let edge=try XCTUnwrap(root.findEntity(named:"edge-0"))
        XCTAssertEqual(edge.transform.scale.z,2,accuracy:0.001)
        ar.showSurfaceGuides=false;XCTAssertFalse(root.isEnabled)
        ar.stop();XCTAssertTrue(ar.view.scene.anchors.isEmpty)
    }
    func testSmoothSeparatedStrokeAndImageRendering() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url=folder.appendingPathComponent("local.json")
        let store=Store(localURL:url)
        try await store.createProject(name:"Storage fixture")
        let project=try XCTUnwrap(store.projects.first)
        try await store.createRoom(in:project,name:"Rendering fixture")
        var room=try XCTUnwrap(store.rooms.first); room.map_path="test-only.worldmap"
        try await store.publishRoom(room)
        let ar=ARController(room:room,mode:.walkthrough); ar.trackingNormal=true
        let a=[Point3(SIMD3<Float>(0,0,0)),Point3(SIMD3(0.3,0,0)),Point3(SIMD3(0.4,0.3,0))]
        let b=[Point3(SIMD3<Float>(2,2,0)),Point3(SIMD3(2.5,2,0))]
        var drawing=Annotation(room:room,kind:.line,pose:.identity,points:a,title:"Zeichnung",detail:""); drawing.strokes=[a,b]
        try await ar.setImage(sampleImage().pngData()!)
        let path="\(project.id.uuidString.lowercased())/\(room.id.uuidString.lowercased())/fixture.png"
        ar.cacheDraftImage(path:path)
        let bytes=try XCTUnwrap(ar.imageData); try await store.uploadAsset(path:path,data:bytes,type:"image/png")
        var image=Annotation(room:room,kind:.image,pose:.identity,points:[Point3(.zero)],title:"Bild",detail:"")
        image.image=SpatialImage(path:path,width:0.4,height:0.25)
        try await store.saveInstruction(image,room:room,replacing:false)
        try await store.saveInstruction(drawing,room:room,replacing:false)
        let reopened=Store(localURL:url)
        XCTAssertEqual(reopened.annotations.first(where:{$0.id==image.id}),image)
        XCTAssertEqual(reopened.annotations.first(where:{$0.id==drawing.id})?.strokes?.count,2)
        let restoredBytes=try await reopened.downloadAsset(path:path)
        XCTAssertEqual(restoredBytes,bytes)
        let restored=try await SpatialImageAsset.prepare(restoredBytes)
        XCTAssertEqual(restored.image.size,ar.draftImage?.size)
        ar.annotations=[drawing,image]; ar.localization.propose(.identity,method:.map); ar.confirm()
        let roots=ar.view.scene.anchors.flatMap { Array($0.children) }
        XCTAssertEqual(roots.first(where:{$0.name==drawing.id.uuidString})?.children.count,2) // Two disconnected tube meshes.
        XCTAssertEqual(roots.first(where:{$0.name==image.id.uuidString})?.children.count,1) // One textured image, no pin.
        XCTAssertNotNil(ar.imageData); XCTAssertNotNil(ar.draftImage)
        ar.stop()
    }
    private func snapshot(_ content:AnyView,store:Store,name:String,size:CGSize) async throws {
        let host=UIHostingController(rootView:content.environmentObject(store))
        let window=UIWindow(frame:CGRect(origin:.zero,size:size))
        if let scene=UIApplication.shared.connectedScenes.first as? UIWindowScene { window.windowScene=scene }
        window.frame=CGRect(origin:.zero,size:size); window.rootViewController=host; window.makeKeyAndVisible()
        defer { window.isHidden=true; window.rootViewController=nil }
        host.view.frame=window.bounds; host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        try await Task.sleep(for:.milliseconds(name.hasPrefix("scan-ready") ? 650 : 180))
        XCTAssertFalse(host.view.hasAmbiguousLayout,name)
        XCTAssertEqual(host.view.bounds.width,size.width,accuracy:1,name)
        let image=UIGraphicsImageRenderer(size:size).image { _ in host.view.drawHierarchy(in:CGRect(origin:.zero,size:size),afterScreenUpdates:true) }
        let attachment=XCTAttachment(image:image); attachment.name=name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
#endif

import SwiftUI
import RealityKit
import UniformTypeIdentifiers
import PhotosUI

enum ARMode: String, Identifiable { case mapping, editing, walkthrough; var id: String { rawValue } }
struct CameraView: UIViewRepresentable {
    let controller: ARController
    func makeUIView(context: Context) -> ARView { controller.view }
    func updateUIView(_ uiView: ARView, context: Context) {}
}
private struct CameraAimPreference: PreferenceKey {
    static var defaultValue: CGPoint? = nil
    static func reduce(value:inout CGPoint?,nextValue:()->CGPoint?) { value=nextValue() ?? value }
}
struct ARScreen: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @StateObject private var ar: ARController
    let manager: Bool
    private let startSession: Bool
    private var room: Room { ar.room }
    private var mode: ARMode { ar.mode }
    @State private var title = ""; @State private var detail = ""
    @State private var replacing: Annotation?
    @State private var priority = 1
    @State private var width: Double = 0.2
    @State private var distance: Double = 1
    @State private var manualDistance = false
    @State private var importing = false; @State private var printing = false
    @State private var taskList = false; @State private var closing = false
    @State private var saving = false
    @State private var tools = true
    @State private var pickingPhoto=false
    @State private var photoSelection: PhotosPickerItem?
    @State private var importingDrawingImage=false
    @State private var imageLoading=false
    @State private var scanMore = false
    @State private var markerExpanded=false
    @State private var showingWorkDetails=false
    @State private var showingPlacement=false
    init(room: Room, mode: ARMode, manager: Bool) {
        self.manager = manager; startSession=true
        _ar = StateObject(wrappedValue: ARController(room: room, mode: mode))
    }
    // Tests inject deterministic states without starting a camera or inventing maps in real flows.
    init(controller:ARController,manager:Bool) {
        self.manager=manager; startSession=false; _ar=StateObject(wrappedValue:controller)
    }
    private var statusTitle: String {
        if mode == .mapping { return ar.scan.canFinish ? "Ready to draw" : "Scanning room" }
        switch ar.localization.state {
        case .aligned: return "Room recognized"
        case .failed: return "Room not recognized"
        case .lost: return "Tracking lost"
        case .verifying: return "Check recovery alignment"
        default: return "Recognizing room…"
        }
    }
    var body: some View {
        ZStack {
            CameraView(controller: ar).ignoresSafeArea()
            if let frame = ar.frozenFrame { FrozenDrawingView(ar:ar,frame:frame).ignoresSafeArea() }
            VStack(spacing: 8) {
                HStack(spacing:8) {
                    Button { closing=true } label: { Image(systemName:"xmark").font(.system(size:20,weight:.semibold)).frame(width:44,height:44) }.accessibilityLabel("Close")
                    Text(room.name).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth:.infinity)
                    Button { ar.resumeCamera(); taskList=true } label: { Image(systemName:"list.bullet").font(.system(size:20,weight:.semibold)).frame(width:44,height:44) }.accessibilityLabel("Tasks")
                }.padding(.horizontal,8).background(.regularMaterial,in:RoundedRectangle(cornerRadius:14))
                VStack(alignment:.leading,spacing:5) {
                    Label(statusTitle,systemImage:ar.localization.state == .aligned ? "checkmark.circle.fill" : "viewfinder").font(.subheadline.weight(.semibold))
                    if mode == .mapping || ar.localization.state != .aligned { Text(ar.guidance).font(.caption).lineLimit(3).fixedSize(horizontal:false,vertical:true) }
                }.frame(maxWidth:.infinity,alignment:.leading).padding(10).background(.regularMaterial,in:RoundedRectangle(cornerRadius:14))
                GeometryReader { proxy in
                    ZStack {
                        Color.clear
                        if mode == .editing || ar.manualActive { Image(systemName:"plus").font(.system(size:20,weight:.semibold)).foregroundStyle(.white).shadow(radius:2).accessibilityHidden(true) }
                    }.preference(key:CameraAimPreference.self,value:CGPoint(x:proxy.frame(in:.global).midX,y:proxy.frame(in:.global).midY))
                }.frame(minHeight:44).allowsHitTesting(false)
                if mode == .mapping || scanMore { ScanOverview(progress: ar.scan) }
                if ar.localization.state == .verifying {
                    VStack {
                        Text("Optional recovery: check that the marker is fixed and the saved reference positions agree.").font(.subheadline)
                        if !room.reference_notes.isEmpty { Text(room.reference_notes).font(.caption) }
                        HStack { Button("Incorrect") { ar.reject() }; Spacer(); Button("Confirm recovery") { ar.confirm() }.buttonStyle(.borderedProminent).disabled(!ar.trackingNormal) }
                    }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                if tools && ar.localization.state != .verifying {
                    VStack(spacing:0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if mode == .mapping {
                                DisclosureGroup("Referenzmarker (optional)",isExpanded:$markerExpanded) { markerTools }.font(.caption)
                            } else {
                                if ar.localization.state == .aligned {
                                    if mode == .editing {
                                        if scanMore {
                                            Text("Move around missed walls and corners. Outlines show detected patches, not full-room coverage.").font(.caption)
                                            Button("Back to drawing") { scanMore=false; ar.showSurfaceGuides=false }
                                        } else { editorTools }
                                        Button(scanMore ? "Hide scan overview" : "Scan more surfaces") { ar.resumeCamera(); scanMore.toggle(); ar.showSurfaceGuides=scanMore }.font(.caption)
                                    } else { Toggle("Show surface outlines", isOn: $ar.showSurfaceGuides).font(.caption) }
                                } else if ar.localization.state != .verifying {
                                    Button("Scan room again") { ar.startMap() }.buttonStyle(.borderedProminent).disabled(!ar.ready)
                                }
                                if room.marker != nil || room.reference_points.count == 2 {
                                    DisclosureGroup("Recovery options") {
                                        if room.marker != nil { Button("Scan fixed marker") { ar.startMarker() } }
                                        if room.reference_points.count == 2 { Button("Align saved reference points") { ar.startManual() } }
                                    }
                                }
                                if ar.manualActive { captureControls }
                                if ar.localization.state == .aligned { Button("Recognize room again") { ar.startMap() }.font(.caption) }
                            }
                        }.padding()
                    }.scrollIndicators(.visible).frame(maxHeight: mode == .mapping ? (markerExpanded ? 200 : 56) : (mode == .walkthrough ? 100 : 200))
                    if mode == .mapping {
                        Divider()
                        Button { saveRoom() } label: { Label("Scan abschließen",systemImage:"pencil.tip").font(.headline).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth:.infinity,minHeight:36) }
                            .buttonStyle(.borderedProminent).disabled(!ar.scan.canFinish || saving).accessibilityIdentifier("scan.finish").padding(12)
                    }
                    if mode == .editing && ar.localization.state == .aligned && !scanMore { Divider(); saveBar.padding(.horizontal,12).padding(.vertical,8) }
                    }.frame(maxWidth:.infinity).background(.regularMaterial,in:RoundedRectangle(cornerRadius:14))
                }
                if mode != .mapping && ar.localization.state != .verifying { Button("Werkzeuge",systemImage:tools ? "chevron.down" : "chevron.up") { tools.toggle() }.font(.caption).padding(.horizontal,12).frame(minHeight:44).background(.regularMaterial,in:Capsule()).accessibilityLabel(tools ? "Werkzeuge ausblenden" : "Werkzeuge einblenden") }
            }.padding(.horizontal, 12).padding(.bottom, 8)
            if saving { Color.black.opacity(0.3).ignoresSafeArea(); ProgressView("Saving room…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
        }
        .onPreferenceChange(CameraAimPreference.self) { point in if let point { ar.aimPoint=ar.view.convert(point,from:nil) } }
        .task { if startSession { await ar.prepare(store:store) } }
        .onDisappear { ar.stop() }
        .onChange(of:title) { _, value in ar.draftText=value }
        .sheet(isPresented:$showingWorkDetails) { DrawingWorkDetails(title:$title,details:$detail,priority:$priority) }
        .sheet(isPresented:$showingPlacement) { DrawingPlacementSettings(measured:$manualDistance,distance:$distance) }
        .photosPicker(isPresented:$pickingPhoto,selection:$photoSelection,matching:.images)
        .onChange(of:photoSelection) { _,item in
            guard let item else { return }
            imageLoading=true
            Task {
                defer { imageLoading=false }
                do { guard let data=try await item.loadTransferable(type:Data.self) else { throw AppError.message("Bild konnte nicht geladen werden.") }; try await ar.setImage(data) }
                catch { ar.error=error.localizedDescription }
            }
        }
        .onChange(of: phase) { _, phase in if phase == .active { ar.resume() } else { ar.suspend() } }
        .alert("AR guidance", isPresented: Binding(get: { ar.error != nil }, set: { if !$0 { ar.error = nil } })) { Button("OK") { ar.error = nil } } message: { Text(ar.error ?? "") }
        .confirmationDialog(mode == .mapping ? "Leave this unsaved scan?" : (ar.draft.isEmpty ? "Close AR? Saved drawings will be kept." : "Discard unsaved drawing and close AR?"), isPresented: $closing, titleVisibility: .visible) {
            Button("Close AR", role: ar.draft.isEmpty && mode != .mapping ? nil : .destructive) { dismiss() }
        }
        .sheet(isPresented: $printing) { if let data = ar.markerData { PrintSheet(data: data) } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png,.jpeg]) { result in
            do {
                let url = try result.get(); guard url.startAccessingSecurityScopedResource() else { throw AppError.message("Cannot read selected file.") }; defer { url.stopAccessingSecurityScopedResource() }
                let data = try Data(contentsOf: url)
                if importingDrawingImage {
                    imageLoading=true
                    Task { defer { imageLoading=false }; do { try await ar.setImage(data) } catch { ar.error=error.localizedDescription } }
                    return
                }
                guard data.count < 20_000_000, let image = UIImage(data: data) else { throw AppError.message("Select an image under 20 MB.") }
                let normalized = UIGraphicsImageRenderer(size: image.size).image { _ in image.draw(in: CGRect(origin: .zero,size: image.size)) }
                guard let png = normalized.pngData() else { return }
                Task { do {
                    if importingDrawingImage { imageLoading=true; defer { imageLoading=false }; try await ar.setImage(png) }
                    else { try await ar.installMarker(data:png,id:UUID(),width:width) }
                } catch { ar.error=error.localizedDescription } }
            } catch { ar.error = error.localizedDescription }
        }
        .sheet(isPresented: $taskList, onDismiss: { Task { await reload() } }) {
            NavigationStack {
                List(ar.annotations) { item in NavigationLink { TaskEditor(item: item, room: room, manager: manager) } label: { Label(item.title, systemImage: item.status == .completed ? "checkmark.circle.fill" : "circle") } }
                    .navigationTitle("Room tasks").toolbar { Button("Done") { taskList = false } }
            }.environmentObject(store)
        }
        .sheet(item: $ar.selected, onDismiss: { Task { await reload() } }) { item in
            NavigationStack { TaskEditor(item: item, room: room, manager: manager, onReposition: mode == .editing && [.line,.area,.image].contains(item.kind) ? {
                replacing = item; ar.clearDraft(); ar.tool = item.kind; title = item.title; detail = item.detail; priority = item.priority; tools = true
                if item.kind == .image {
                    imageLoading=true
                    Task { defer { imageLoading=false }; do { try await ar.restoreImageDraft(item,store:store) } catch { ar.error=error.localizedDescription } }
                }
            } : nil) }.environmentObject(store)
        }
    }
    private var markerTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Only needed if scanning the room later is unreliable. Use a unique, permanently fixed print with its measured width.").font(.caption)
            HStack {
                Button("Generate print") { let id = UUID(); let data = MarkerPrint.make(id: id); Task { do { try await ar.installMarker(data: data, id: id, width: width); printing = true } catch { ar.error = error.localizedDescription } } }
                Button("Import image") { importingDrawingImage=false; importing = true }
                if ar.markerData != nil { Button("Print / Share") { printing = true } }
            }
            HStack { Text("Print width (m)"); TextField("0.20", value: $width, format: .number).keyboardType(.decimalPad).textFieldStyle(.roundedBorder) }
            Button("Apply measured width") {
                guard let data = ar.markerData, let id = ar.markerID else { return }
                Task { do { try await ar.installMarker(data: data, id: id, width: width) } catch { ar.error = error.localizedDescription } }
            }
            Button(ar.markerRegistered ? "Marker registered ✓" : "Register detected marker") { ar.registerMarker() }.disabled(!ar.ready)
        }.padding(.top, 8)
    }
    private var captureControls: some View {
        VStack(alignment: .leading) {
            Button(ar.tool == .area ? "Add corner at crosshair" : "Place at crosshair", systemImage: "scope") { ar.capture(distance: manualDistance ? Float(distance) : nil) }
                .buttonStyle(.bordered).disabled(!ar.trackingNormal || (manualDistance && (!distance.isFinite || distance < 0.1 || distance > 10)))
            Button("Abstand einstellen",systemImage:"ruler") { showingPlacement=true }.font(.caption)
        }
    }
    private var editorTools: some View {
        VStack(alignment:.leading,spacing:10) {
            if let replacing { Text("Repositioning: \(replacing.title)").font(.headline); Button("Cancel") { self.replacing=nil; ar.clearDraft(); ar.resumeCamera(); title=""; detail="" } }
            Picker("Werkzeug",selection:Binding(get:{ar.tool},set:selectTool)) {
                Text("Zeichnen").tag(AnnotationKind.line); Text("Fläche").tag(AnnotationKind.area); Text("Bild").tag(AnnotationKind.image)
            }.pickerStyle(.segmented).accessibilityIdentifier("drawing.tools")
            ViewThatFits(in:.horizontal) {
                HStack { lockButton.fixedSize(); if ar.tool == .image { Spacer(); imageButton.fixedSize() } }
                VStack(alignment:.leading,spacing:8) { lockButton; if ar.tool == .image { imageButton } }
            }
            if ar.tool == .image {
                if imageLoading { ProgressView("Bild wird geladen…") }
                else if let image=ar.draftImage {
                    HStack(spacing:10) {
                        Image(uiImage:image).resizable().scaledToFit().frame(width:44,height:40).accessibilityHidden(true)
                        VStack(alignment:.leading) { Text("Breite").font(.caption); Text("\(ar.imageWidth,format:.number.precision(.fractionLength(2))) m").font(.caption.monospacedDigit()) }
                        Spacer(minLength:4)
                        let maximum=min(Float(3),3/Float(image.size.height/image.size.width))
                        Stepper("Bildbreite",value:$ar.imageWidth,in:min(0.05,maximum)...maximum,step:0.05).labelsHidden().fixedSize().accessibilityLabel("Bildbreite")
                    }
                }
                Text("Bild auf der Oberfläche antippen und platzieren.").font(.caption).fixedSize(horizontal:false,vertical:true)
                Button("Aus Datei auswählen",systemImage:"folder") { importingDrawingImage=true; importing=true }.font(.subheadline)
            } else {
                Text(ar.tool == .line ? "Ziehen zum Zeichnen. Loslassen beendet den Strich." : "Ecken einer Fläche antippen.").font(.caption)
            }
            if ar.tool != .line { DisclosureGroup("Genaue Platzierung") { captureControls } }
            Button("Arbeitsanweisung",systemImage:"text.alignleft") { showingWorkDetails=true }.font(.subheadline).frame(minHeight:44)
        }
    }
    private var lockButton: some View {
        Button(ar.frozenFrame == nil ? "Ansicht fixieren" : "Live-Kamera",systemImage:ar.frozenFrame == nil ? "viewfinder" : "camera") { ar.freezeView() }
            .font(.subheadline).lineLimit(1).disabled(!ar.trackingNormal).accessibilityIdentifier("drawing.lock").frame(minHeight:44)
    }
    private var imageButton: some View {
        Button("Bild wählen",systemImage:"photo") { pickingPhoto=true }.font(.subheadline).lineLimit(1).frame(minHeight:44).accessibilityIdentifier("drawing.image")
    }
    private var saveBar: some View {
        HStack(spacing:10) {
            Button { ar.undoPoint() } label: { Image(systemName:"arrow.uturn.backward").frame(width:22,height:22) }
                .buttonStyle(.bordered).frame(minWidth:44,minHeight:44).accessibilityLabel(ar.tool == .line ? "Strich zurück" : "Zurück").disabled(ar.draft.isEmpty)
            Button { ar.clearDraft() } label: { Image(systemName:"trash").frame(width:22,height:22) }
                .buttonStyle(.bordered).frame(minWidth:44,minHeight:44).accessibilityLabel("Leeren").disabled(ar.draft.isEmpty && ar.drawingPlane == nil)
            Button { saveDrawing() } label: { Label("Speichern",systemImage:"checkmark").font(.headline).lineLimit(1).minimumScaleFactor(0.75).frame(maxWidth:.infinity,minHeight:36) }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("drawing.save").disabled(ar.draft.isEmpty || saving || imageLoading)
        }
    }
    private func selectTool(_ kind:AnnotationKind) {
        guard kind == ar.tool || ar.draft.isEmpty else { ar.error="Bitte die aktuelle Zeichnung zuerst speichern oder leeren."; return }
        ar.tool=kind
        if kind == .image && ar.draftImage == nil { pickingPhoto=true }
    }
    private func saveDrawing() {
        saving = true
        Task {
            defer { saving = false }
            do {
                let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
                var attachment:SpatialImage?
                if ar.tool == .image {
                    guard ar.imageData != nil else { pickingPhoto=true; return }
                    let path="\(room.project_id.uuidString.lowercased())/\(room.id.uuidString.lowercased())/\(UUID().uuidString.lowercased()).png"
                    attachment=SpatialImage(path:path,width:ar.imageWidth,height:ar.imageHeight)
                }
                var item = try ar.makeAnnotation(kind: ar.tool, title: label.isEmpty ? (ar.tool == .area ? "Fläche" : (ar.tool == .image ? "Bild" : "Zeichnung")) : label, detail: detail, priority: priority,image:attachment)
                if let attachment,let data=ar.imageData {
                    try await store.uploadAsset(path:attachment.path,data:data,type:"image/png"); ar.cacheDraftImage(path:attachment.path)
                }
                if let replacing { item.id = replacing.id; item.status = replacing.status }
                try await store.saveInstruction(item, room: room, replacing: replacing != nil)
                replacing = nil; ar.clearDraft(); ar.resumeCamera(); title = ""; detail = ""; await reload()
            } catch { ar.error = error.localizedDescription }
        }
    }
    private func saveRoom() {
        saving = true
        Task {
            defer { saving = false }
            do { let updated = try await ar.saveMap(store: store); ar.beginEditing(updated) }
            catch { ar.error = "Room not saved. Keep this session open and retry. \(error.localizedDescription)" }
        }
    }
    private func reload() async {
        do { try await store.loadAnnotations(room); await ar.reload(store.annotations.filter { $0.room_id == room.id },store:store) } catch { ar.error = error.localizedDescription }
    }
}

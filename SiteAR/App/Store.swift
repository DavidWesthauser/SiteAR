import SwiftUI

/// On-device persistence while cloud accounts are not configured. Starts empty.
private struct LocalData: Codable {
    var projects: [Project] = []; var rooms: [Room] = []; var annotations: [Annotation] = []
    static let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

@MainActor final class Store: ObservableObject {
    @Published var projects: [Project] = []
    @Published var rooms: [Room] = []
    @Published var annotations: [Annotation] = []
    @Published var signedIn = false
    @Published var busy = false
    @Published var error: String?
    @Published private(set) var isLocalMode = false
    let backend: Backend?
    private var localURL: URL?
    init() {
        do { let client = Backend(config: try .load()); backend = client; signedIn = client.user != nil }
        catch {
            backend = nil
            #if DEBUG && os(iOS)
            let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SiteAR/local.json")
            openLocal(at: url)
            #else
            self.error = error.localizedDescription
            #endif
        }
    }
    /// Explicit local storage entry point; never changes cloud authentication or Keychain.
    init(localURL: URL) { backend = nil; openLocal(at: localURL) }
    init(backend: Backend) { self.backend = backend; signedIn = backend.user != nil }
    private func openLocal(at url: URL) {
        do {
            let data: LocalData
            if FileManager.default.fileExists(atPath: url.path) { data = try JSONDecoder().decode(LocalData.self, from: Data(contentsOf: url)) }
            else { data = LocalData(); try persist(data, at: url) }
            localURL = url; isLocalMode = true; signedIn = true; apply(data)
        } catch { self.error = "Could not open local data: \(error.localizedDescription)" }
    }
    private func persist(_ data: LocalData, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(data).write(to: url, options: .atomic)
    }
    private func apply(_ data: LocalData) { projects = data.projects; rooms = data.rooms; annotations = data.annotations }
    private func changeLocal(_ operation: (inout LocalData) throws -> Void) throws {
        guard isLocalMode, let localURL else { throw AppError.message("Local storage is not active.") }
        var data = LocalData(projects: projects, rooms: rooms, annotations: annotations)
        try operation(&data); try persist(data, at: localURL); apply(data)
    }
    var userID: UUID? { isLocalMode ? LocalData.userID : backend?.user?.id }
    func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true
        Task { defer { busy = false }; do { try await operation() } catch { self.error = error.localizedDescription } }
    }
    func client() throws -> Backend { guard let backend else { throw AppError.message(isLocalMode ? "Cloud sharing requires Supabase. Your room data is saved on this device." : "Backend is not configured. See README.") }; return backend }
    func loadProjects() async throws {
        guard !isLocalMode else { return }
        projects = try await client().list("projects", query: "&order=name")
    }
    func loadRooms(_ project: Project) async throws {
        guard !isLocalMode else { return }
        rooms = try await client().list("rooms", query: "&project_id=eq.\(project.id)&order=name")
    }
    func room(id: UUID) async throws -> Room {
        if isLocalMode, let room = rooms.first(where: { $0.id == id }) { return room }
        let values: [Room] = try await client().list("rooms", query: "&id=eq.\(id)")
        guard let room = values.first else { throw AppError.message("Room no longer exists or access was removed.") }; return room
    }
    func loadAnnotations(_ room: Room) async throws {
        guard !isLocalMode else { return }
        let values: [Annotation] = try await client().list("annotations", query: "&room_id=eq.\(room.id)&order=title")
        try room.validate(); try values.forEach { try $0.validate(room: room) }; annotations = values
    }
    private func name(_ value: String) throws -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 120 else { throw AppError.message("Use a name between 1 and 120 characters.") }; return text
    }
    func createProject(name value: String) async throws {
        guard let owner = userID else { throw AppError.message("Please sign in.") }
        let project = Project(owner_id: owner, name: try name(value))
        if isLocalMode { try changeLocal { $0.projects.append(project) } }
        else { try await client().insert("projects", value: project); try await loadProjects() }
    }
    func renameProject(_ project: Project, name value: String) async throws {
        let title = try name(value)
        if isLocalMode { try changeLocal { data in
            guard let i = data.projects.firstIndex(where: { $0.id == project.id }) else { throw AppError.message("Project no longer exists.") }; data.projects[i].name = title
        } } else { try await client().update("projects", id: project.id, value: ["name": title]); try await loadProjects() }
    }
    func deleteProject(_ project: Project) async throws {
        if isLocalMode { try changeLocal { data in
            let roomIDs = Set(data.rooms.filter { $0.project_id == project.id }.map(\.id))
            data.annotations.removeAll { roomIDs.contains($0.room_id) }; data.rooms.removeAll { $0.project_id == project.id }; data.projects.removeAll { $0.id == project.id }
        } } else { try await client().delete("projects", id: project.id); try await loadProjects() }
    }
    func createRoom(in project: Project, name value: String) async throws {
        let room = Room(project_id: project.id, name: try name(value))
        if isLocalMode { try changeLocal { $0.rooms.append(room) } }
        else { try await client().insert("rooms", value: room); try await loadRooms(project) }
    }
    func renameRoom(_ room: Room, name value: String) async throws {
        let title = try name(value)
        if isLocalMode { try changeLocal { data in
            guard let i = data.rooms.firstIndex(where: { $0.id == room.id }) else { throw AppError.message("Room no longer exists.") }; data.rooms[i].name = title
        } } else { try await client().update("rooms", id: room.id, value: ["name": title]) }
    }
    func deleteRoom(_ room: Room) async throws {
        if isLocalMode { try changeLocal { data in data.annotations.removeAll { $0.room_id == room.id }; data.rooms.removeAll { $0.id == room.id } } }
        else { try await client().delete("rooms", id: room.id) }
    }
    func saveTask(_ item: Annotation, room: Room, manager: Bool) async throws {
        try item.validate(room: room)
        if isLocalMode { try changeLocal { data in
            guard let i = data.annotations.firstIndex(where: { $0.id == item.id }) else { throw AppError.message("Task no longer exists.") }; data.annotations[i] = item
        } } else if manager { try await client().update("annotations", id: item.id, value: item) }
        else { try await client().rpc("set_task_status", arguments: ["task": item.id.uuidString, "new_status": item.status.rawValue]) }
        try await loadAnnotations(room)
    }
    func deleteTask(_ item: Annotation, room: Room) async throws {
        if isLocalMode { try changeLocal { $0.annotations.removeAll { $0.id == item.id } } }
        else { try await client().delete("annotations", id: item.id); try await loadAnnotations(room) }
    }
}

extension Store {
    private func assetURL(_ path: String) throws -> URL {
        guard let localURL, !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw AppError.message("Invalid asset path.") }
        return localURL.deletingLastPathComponent().appendingPathComponent("assets").appendingPathComponent(path)
    }
    func downloadAsset(path: String) async throws -> Data {
        if isLocalMode { return try Data(contentsOf: assetURL(path)) }
        return try await client().download(path: path)
    }
    func uploadAsset(path: String, data: Data, type: String) async throws {
        if isLocalMode {
            let url = try assetURL(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } else { try await client().upload(path: path, data: data, type: type) }
    }
    func publishRoom(_ room: Room) async throws {
        try room.validate()
        if isLocalMode { try changeLocal { data in
            guard let i = data.rooms.firstIndex(where: { $0.id == room.id }), data.rooms[i].coordinate_id == room.coordinate_id else { throw AppError.message("Room coordinate system changed. Reopen the room.") }
            let old = data.rooms[i]
            if old.map_path != nil && (old.map_path != room.map_path || old.marker != room.marker || old.reference_points != room.reference_points || old.reference_notes != room.reference_notes || old.surfaces != room.surfaces) { throw AppError.message("Published room maps cannot be replaced. Create a new room for remapping.") }
            data.rooms[i] = room
        } } else { try await client().update("rooms", id: room.id, value: room) }
    }
    func saveInstruction(_ item: Annotation, room: Room, replacing: Bool) async throws {
        try item.validate(room: room)
        guard room.map_path != nil else { throw AppError.message("Map the room before placing instructions.") }
        if isLocalMode { try changeLocal { data in
            guard data.rooms.contains(where: { $0.id == room.id && $0.coordinate_id == room.coordinate_id && $0.map_path != nil }) else { throw AppError.message("Saved room map unavailable.") }
            if replacing {
                guard let i = data.annotations.firstIndex(where: { $0.id == item.id && $0.room_id == room.id }) else { throw AppError.message("Instruction no longer exists.") }
                data.annotations[i] = item
            } else { data.annotations.append(item) }
        } } else if replacing { try await client().update("annotations", id: item.id, value: item) }
        else { try await client().insert("annotations", value: item) }
    }
}

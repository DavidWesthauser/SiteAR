import SwiftUI

struct AuthenticationView: View {
    @EnvironmentObject var store: Store
    @State private var email = ""; @State private var password = ""; @State private var register = false
    @State private var notice = ""
    var body: some View {
        NavigationStack {
            Form {
                Section { Label("Instructions anchored to your workplace", systemImage: "arkit").font(.headline) }
                Section(register ? "Create account" : "Welcome back") {
                    TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("auth.email")
                    SecureField("Password (at least 8 characters)", text: $password).textContentType(register ? .newPassword : .password).accessibilityIdentifier("auth.password")
                    Button(register ? "Register" : "Sign in") {
                        store.run {
                            let active = try await store.client().authenticate(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password, register: register)
                            if active { store.signedIn = true } else { notice = "Check your email to confirm your account, then sign in." }
                        }
                    }.disabled(email.isEmpty || password.count < 8 || store.busy).accessibilityIdentifier("auth.submit")
                    Toggle("I need an account", isOn: $register)
                    if !notice.isEmpty { Text(notice) }
                }
                Section { Text("Camera access is requested only when opening AR. SiteAR supports camera-only world tracking; LiDAR is optional.").font(.footnote) }
            }.navigationTitle("SiteAR")
        }
    }
}
struct ProjectDashboard: View {
    @EnvironmentObject var store: Store
    @State private var creating = false; @State private var name = ""
    var body: some View {
        NavigationStack {
            List {
                if store.projects.isEmpty { ContentUnavailableView("Your sites", systemImage: "building.2", description: Text(store.isLocalMode ? "Create your first project, add a room, then map it with your iPhone." : "Create a project or ask a manager to share one with your registered email.")) }
                ForEach(store.projects) { project in NavigationLink(value: project.id) { Label(project.name, systemImage: "building.2") } }
            }
            .navigationTitle("Projects").accessibilityIdentifier("projects.list")
            .navigationDestination(for: UUID.self) { id in
                if let project = store.projects.first(where: { $0.id == id }) { ProjectDetail(project: project) }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("New project", systemImage: "plus") { name = ""; creating = true }.accessibilityIdentifier("projects.new") }
                ToolbarItem(placement: .topBarLeading) { NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") } }
            }
            .alert("New project", isPresented: $creating) {
                TextField("Project name", text: $name)
                Button("Create") { let title = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !title.isEmpty else { return }; store.run {
                    try await store.createProject(name: title)
                } }
                Button("Cancel", role: .cancel) {}
            }
            .task { do { try await store.loadProjects() } catch { store.error = error.localizedDescription } }
            .refreshable { do { try await store.loadProjects() } catch { store.error = error.localizedDescription } }
        }
    }
}
struct ProjectDetail: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let project: Project
    @State private var name = ""; @State private var email = ""
    @State private var addRoom = false; @State private var rename = false; @State private var deleting = false
    var manager: Bool { project.owner_id == store.userID }
    var body: some View {
        List {
            Section("Rooms") {
                ForEach(store.rooms.filter { $0.project_id == project.id }) { room in
                    NavigationLink { RoomDetail(project: project, initialRoom: room) } label: {
                        VStack(alignment: .leading) { Text(room.name); Text(room.map_path == nil ? "Needs mapping" : "Spatial map saved").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if manager { Button("Add room", systemImage: "plus") { name = ""; addRoom = true }.accessibilityIdentifier("rooms.new") }
            }
            if manager {
                if !store.isLocalMode { Section("Grant worker access") {
                    TextField("Registered worker email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Share project") { store.run { try await store.client().rpc("share_project", arguments: ["project": project.id.uuidString, "worker_email": email]); email = "" } }.disabled(email.isEmpty)
                    NavigationLink("Manage worker access") { MembersView(project: project) }
                } }
                Section("Project") {
                    Button("Rename project") { name = project.name; rename = true }
                    Button("Delete project and all rooms", role: .destructive) { deleting = true }
                }
            }
        }.navigationTitle(project.name)
        .task { do { try await store.loadRooms(project) } catch { store.error = error.localizedDescription } }
        .refreshable { do { try await store.loadRooms(project) } catch { store.error = error.localizedDescription } }
        .alert("Add room", isPresented: $addRoom) {
            TextField("Room name", text: $name)
            Button("Add") { let title = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !title.isEmpty else { return }; store.run { try await store.createRoom(in: project, name: title) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename project", isPresented: $rename) {
            TextField("Name", text: $name)
            Button("Save") { guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; store.run { try await store.renameProject(project, name: name); dismiss() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Permanently delete this project, its rooms and instructions?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete project", role: .destructive) { store.run { try await store.deleteProject(project); dismiss() } }
        }
    }
}
struct Membership: Decodable, Identifiable { let project_id: UUID; let user_id: UUID; var id: UUID { user_id } }
struct MembersView: View {
    @EnvironmentObject var store: Store
    let project: Project
    @State private var members: [Membership] = []
    var body: some View {
        List(members) { member in
            VStack(alignment: .leading) {
                Text(member.user_id.uuidString).font(.caption).textSelection(.enabled)
                Button("Revoke worker access", role: .destructive) { store.run { try await store.client().rpc("revoke_worker", arguments: ["project": project.id.uuidString, "worker": member.user_id.uuidString]); try await load() } }
            }
        }.navigationTitle("Workers").task { do { try await load() } catch { store.error = error.localizedDescription } }
    }
    func load() async throws { members = try await store.client().list("memberships", query: "&project_id=eq.\(project.id)") }
}
struct RoomDetail: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let project: Project; let initialRoom: Room
    @State private var room: Room?
    @State private var arMode: ARMode?
    @State private var rename = false; @State private var deleting = false; @State private var name = ""
    var current: Room { room ?? initialRoom }
    var manager: Bool { project.owner_id == store.userID }
    var body: some View {
        List {
            Section("Spatial room") {
                if current.map_path != nil {
                    Button("Start AR walkthrough", systemImage: "arkit") { arMode = .walkthrough }
                    if manager { Button("Edit AR instructions", systemImage: "pencil.tip.crop.circle") { arMode = .editing } }
                    Text("Scan the room from familiar viewpoints. Your saved drawings appear when the room is recognized.").font(.footnote)
                } else if manager { Button("Map room", systemImage: "camera.viewfinder") { arMode = .mapping } }
                else { Text("Ask the manager to map this room.") }
            }
            Section("Tasks · available without AR") {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    let tasks = store.annotations.filter { $0.room_id == current.id && $0.status == status }
                    if !tasks.isEmpty {
                        Text(status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption).foregroundStyle(.secondary)
                        ForEach(tasks) { item in NavigationLink { TaskEditor(item: item, room: current, manager: manager) } label: { VStack(alignment: .leading) { Text(item.title); Text(item.detail).lineLimit(2).font(.caption) } } }
                    }
                }
                if !store.annotations.contains(where: { $0.room_id == current.id }) { Text("No instructions yet").foregroundStyle(.secondary) }
            }
            if manager {
                Section {
                    Button("Rename room") { name = current.name; rename = true }
                    Button("Delete room", role: .destructive) { deleting = true }
                }
            }
        }.navigationTitle(current.name)
        .task { await refresh() }.refreshable { await refresh() }
        .fullScreenCover(item: $arMode, onDismiss: { Task { await refresh() } }) { mode in ARScreen(room: current, mode: mode, manager: manager).environmentObject(store) }
        .alert("Rename room", isPresented: $rename) {
            TextField("Name", text: $name)
            Button("Save") { guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; store.run { try await store.renameRoom(current, name: name); await refresh() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Permanently delete this room and its instructions?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete room", role: .destructive) { store.run { try await store.deleteRoom(current); dismiss() } }
        }
    }
    func refresh() async {
        do {
            let loaded = try await store.room(id: initialRoom.id)
            room = loaded; try await store.loadAnnotations(loaded)
        } catch { store.error = error.localizedDescription }
    }
}
struct TaskEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var item: Annotation
    let room: Room; let manager: Bool
    @State private var deleting = false
    @State private var discarding = false
    private let original: Annotation
    private let onReposition: (() -> Void)?
    init(item: Annotation, room: Room, manager: Bool, onReposition: (() -> Void)? = nil) {
        _item = State(initialValue: item); original = item; self.room = room; self.manager = manager; self.onReposition = onReposition
    }
    var body: some View {
        Form {
            Section("Instruction") {
                if manager { TextField("Title", text: $item.title, axis:.vertical).lineLimit(1...3); TextField("Description", text: $item.detail, axis: .vertical); Picker("Priority", selection: $item.priority) { Text("Low").tag(0); Text("Normal").tag(1); Text("High").tag(2) } }
                else { Text(item.title).font(.headline); Text(item.detail) }
            }
            Picker("Status", selection: $item.status) { ForEach(TaskStatus.allCases, id: \.self) { Text($0.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).tag($0) } }
            Button("Save task") { store.run {
                try await store.saveTask(item, room: room, manager: manager); dismiss()
            } }.disabled(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if manager, let onReposition { Button("Reposition geometry in AR") { onReposition(); dismiss() }.disabled(item != original) }
            if manager { Button("Delete instruction", role: .destructive) { deleting = true } }
        }.navigationTitle("Task")
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(item != original)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Back") { if item != original { discarding = true } else { dismiss() } } } }
        .confirmationDialog("Discard unsaved task edits?", isPresented: $discarding, titleVisibility: .visible) { Button("Discard changes", role: .destructive) { dismiss() } }
        .confirmationDialog("Delete this spatial instruction?", isPresented: $deleting) {
            Button("Delete", role: .destructive) { store.run { try await store.deleteTask(item, room: room); dismiss() } }
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Form {
            if store.isLocalMode { Section("On this device") { Text("No account connected"); Text("Your projects, room maps and instructions are saved on this device. Configure Supabase to enable accounts and project sharing.").font(.footnote) } }
            else { Section("Account") { Text(store.backend?.user?.email ?? "Signed in"); Button("Sign out", role: .destructive) { store.run { await store.backend?.signOut(); store.projects = []; store.rooms = []; store.annotations = []; store.signedIn = false } } } }
            Section("SiteAR 1.0") { Text("Spatial work instructions · iOS 17+"); Text("Room maps and marker images are private project assets. Accuracy depends on lighting, texture and fixed reference points. Always check alignment before work.").font(.footnote) }
        }.navigationTitle("Settings")
    }
}

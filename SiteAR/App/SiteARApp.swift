import SwiftUI
@main struct SiteARApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup {
            Group { if store.signedIn { ProjectDashboard() } else { AuthenticationView() } }
                .environmentObject(store)
                .alert("SiteAR", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
                .overlay { if store.busy { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        }
    }
}

import SwiftUI

@main
struct KaliberfinderApp: App {
    @StateObject private var scale = ScaleModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
            }
            .environmentObject(scale)
        }
    }
}

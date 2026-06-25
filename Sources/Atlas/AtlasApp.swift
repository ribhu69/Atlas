import SwiftUI

@main
struct AtlasApp: App {
    @State private var appVM = AppViewModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appVM)
        }
    }
}

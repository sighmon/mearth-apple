import SwiftUI

@main
struct MearthApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
#if os(macOS)
        .windowStyle(.hiddenTitleBar)
#endif
    }
}

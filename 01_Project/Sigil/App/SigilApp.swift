import SwiftUI

@main
struct SigilApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 720, minHeight: 560)
                .preferredColorScheme(.dark)
                .environment(appState)
                .task {
                    await appState.bootstrap()
                }
        }
        .defaultSize(width: 1000, height: 720)
        .windowStyle(.hiddenTitleBar)
        .commands {
            SidebarCommands()
        }
    }
}

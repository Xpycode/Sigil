import SwiftUI

@main
struct SigilApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 720, minHeight: 480)
                .preferredColorScheme(.dark)
                .environment(appState)
                .task {
                    await appState.bootstrap()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            SidebarCommands()
        }
    }
}

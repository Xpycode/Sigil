import SwiftUI

struct ContentView: View {
    @AppStorage("showSidebar") private var showSidebar: Bool = true
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        HSplitView {
            if showSidebar {
                SidebarView()
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
            }
            VolumeDetailView()
                .frame(minWidth: 500)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.primaryBackground)
        .sigilAlert(title: "Something went wrong", message: $appState.lastError)
        .sigilAlert(title: "Volume memory recovered", message: $appState.lastLoadWarning)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                PaneToggleButton(
                    isOn: $showSidebar,
                    iconName: "sidebar.left",
                    help: "Toggle Sidebar"
                )
            }
            ToolbarItemGroup(placement: .primaryAction) {
                PaneToggleButton(
                    isOn: $appState.showAllVolumes,
                    iconName: "eye",
                    help: "Show All Volumes (incl. system, DMGs)"
                )
            }
        }
        .toolbarRole(.editor)
    }
}

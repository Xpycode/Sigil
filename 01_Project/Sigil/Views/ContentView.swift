import SwiftUI

struct ContentView: View {
    @AppStorage("showSidebar") private var showSidebar: Bool = true
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        HSplitView {
            if showSidebar {
                SidebarView()
                    .frame(minWidth: 220, idealWidth: 280, maxWidth: 480)
            }
            VolumeDetailView()
                .frame(minWidth: 440)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.primaryBackground)
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

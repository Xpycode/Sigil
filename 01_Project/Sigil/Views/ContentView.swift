import SwiftUI

struct ContentView: View {
    @AppStorage("showSidebar") private var showSidebar: Bool = true
    @AppStorage("showAllVolumes") private var showAllVolumes: Bool = false

    var body: some View {
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
                    isOn: $showAllVolumes,
                    iconName: "eye",
                    help: "Show All Volumes (incl. system, DMGs)"
                )
            }
        }
        .toolbarRole(.editor)
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 600)
        .preferredColorScheme(.dark)
}

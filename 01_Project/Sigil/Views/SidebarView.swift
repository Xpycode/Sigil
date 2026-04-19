import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedID) {
            Section("Mounted") {
                if appState.mounted.isEmpty {
                    emptyRow("(no mounted volumes)")
                } else {
                    ForEach(appState.mounted) { info in
                        VolumeRow(
                            name: info.name,
                            subtitle: info.format ?? "—",
                            isMounted: true,
                            isRemembered: isRemembered(info)
                        )
                        .tag(info.id)
                    }
                }
            }

            Section("Remembered") {
                if appState.rememberedNotMounted.isEmpty {
                    emptyRow("(no remembered volumes)")
                } else {
                    ForEach(appState.rememberedNotMounted) { record in
                        VolumeRow(
                            name: record.name,
                            subtitle: record.note.isEmpty ? "—" : record.note,
                            isMounted: false,
                            isRemembered: true  // By definition.
                        )
                        .tag(record.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.primaryBackground)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(Theme.tertiaryText)
            .listRowBackground(Color.clear)
    }

    /// Is this mounted volume currently in Sigil's store?
    private func isRemembered(_ info: VolumeInfo) -> Bool {
        guard let id = info.identity else { return false }
        return appState.remembered.contains { $0.identity == id }
    }
}

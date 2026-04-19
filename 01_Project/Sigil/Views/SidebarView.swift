import SwiftUI

/// Wave 1 placeholder. Live volume sections wired in Wave 3.
struct SidebarView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Mounted")
            placeholderRow("(no mounted volumes)")

            sectionHeader("Remembered")
            placeholderRow("(no remembered volumes)")

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.primaryBackground)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    private func placeholderRow(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(Theme.tertiaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
    }
}

#Preview {
    SidebarView()
        .frame(width: 280, height: 480)
        .preferredColorScheme(.dark)
}

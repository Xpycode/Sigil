import SwiftUI

/// Wave 1 placeholder. Empty-state polish + editor wired in Wave 7.
struct VolumeDetailView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("Select a volume")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
            Text("Mount an external drive or pick a remembered one in the sidebar.")
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.secondaryBackground)
    }
}

#Preview {
    VolumeDetailView()
        .frame(width: 600, height: 480)
        .preferredColorScheme(.dark)
}

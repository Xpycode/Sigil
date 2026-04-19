import SwiftUI

/// Destructive-action confirmation sheet. Reused for Reset and Forget so the
/// mental model stays consistent.
struct ConfirmationSheet: View {
    let title: String
    let message: String
    let destructiveTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.accent)

            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.primaryText)

            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                Button(destructiveTitle, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 440)
        .background(Theme.primaryBackground)
    }
}

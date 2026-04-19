import SwiftUI

extension View {
    /// Present a standard alert when the bound optional message is non-nil.
    /// Tapping OK clears the message.
    func sigilAlert(title: String, message: Binding<String?>) -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { presenting in if !presenting { message.wrappedValue = nil } }
            ),
            presenting: message.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) { message.wrappedValue = nil }
        } message: { text in
            Text(text)
        }
    }
}

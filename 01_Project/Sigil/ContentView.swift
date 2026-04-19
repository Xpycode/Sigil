import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)
            Text("Sigil")
                .font(.system(size: 28, weight: .semibold))
            Text("Wave 0 — empty skeleton")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.10))
    }
}

#Preview {
    ContentView()
        .frame(width: 720, height: 480)
}

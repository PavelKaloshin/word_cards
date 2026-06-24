import SwiftUI

struct HUDView: View {
    let hud: SessionHUD

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .foregroundStyle(.green)
                Text("\(hud.good)")
                    .fontWeight(.medium)
            }

            HStack(spacing: 4) {
                Image(systemName: "xmark")
                    .foregroundStyle(.red)
                Text("\(hud.again)")
                    .fontWeight(.medium)
            }

            Text("\(Int(hud.accuracy * 100))%")
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(hud.position)/\(hud.total)")
                .foregroundStyle(.secondary)

            Text(hud.mode == .learn ? "learn" : "review")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(hud.mode == .learn ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2))
                .clipShape(Capsule())
        }
        .font(.subheadline)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

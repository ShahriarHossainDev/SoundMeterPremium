import SwiftUI

struct ProView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(AppTheme.accent)
                    .padding(22)
                    .background(AppTheme.accent.opacity(0.12), in: Circle())

                Text("SoundMeter Pro")
                    .font(.largeTitle.bold())

                Text("Unlock a deeper understanding of your sound environment.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                PremiumCard {
                    VStack(alignment: .leading, spacing: 14) {
                        ProFeatureRow(title: "Advanced spectrum analysis", subtitle: "Explore frequency content")
                        ProFeatureRow(title: "PDF reports", subtitle: "Share polished measurement summaries")
                        ProFeatureRow(title: "Unlimited session history", subtitle: "Keep your measurements organized")
                        ProFeatureRow(title: "Cloud sync", subtitle: "Access sessions across devices")
                    }
                }

                Text("This is a preview paywall. No purchase is processed yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Go Pro")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProFeatureRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

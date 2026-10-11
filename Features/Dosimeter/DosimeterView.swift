import SwiftUI

/// Exposure monitoring becomes available once the calibrated Leq engine is enabled.
struct DosimeterView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Dosimeter").font(.largeTitle.bold())
                PremiumCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Exposure monitoring", systemImage: "headphones")
                            .font(.headline)
                        Text("NIOSH and OSHA dose calculations require calibrated weighted sound pressure levels. They will be enabled with the measurement-engine upgrade.")
                            .foregroundStyle(.secondary)
                        Label("Not recording yet", systemImage: "pause.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                PremiumCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Why this is separate").font(.headline)
                        Text("The Meter answers “how loud is it now?” A dosimeter tracks cumulative exposure across a work period.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Dosimeter")
    }
}

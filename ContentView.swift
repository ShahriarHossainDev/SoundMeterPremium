import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationStack { CameraView() }
                .tabItem { Label("Camera", systemImage: "camera") }

            NavigationStack { DosimeterView() }
                .tabItem { Label("Dosimeter", systemImage: "headphones") }

            NavigationStack { MeterView() }
                .tabItem { Label("Meter", systemImage: "gauge.with.dots.needle.67percent") }

            HistoryView()
                .tabItem { Label("Data", systemImage: "list.bullet.rectangle") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
    }
}

struct SpectrumView: View {
    @StateObject private var model = SpectrumViewModel()
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PremiumCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Frequency Analyzer", systemImage: "waveform.path")
                            .font(.title2.bold())
                        Text("Live FFT frequency analyzer using the device microphone.")
                            .foregroundStyle(.secondary)
                    }
                }

                PremiumCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Live spectrum").font(.headline)
                            Spacer()
                            Text(model.dominantFrequency > 0 ? String(format: "%.0f Hz", model.dominantFrequency) : "Listening…")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        HStack(alignment: .bottom, spacing: 5) {
                            ForEach(Array(model.bars.enumerated()), id: \.offset) { _, height in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(LinearGradient(colors: [AppTheme.accent, AppTheme.secondaryAccent], startPoint: .bottom, endPoint: .top))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 130 * CGFloat(height))
                            }
                        }
                        Text("Dominant frequency is the strongest FFT bin. Results are for indication, not laboratory analysis.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Spectrum")
        .task { model.start() }
        .onDisappear { model.stop() }
        .alert("Spectrum", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

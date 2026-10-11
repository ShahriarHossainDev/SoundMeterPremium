import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("defaultWeighting") private var weighting = "Z"
    @AppStorage("responseTime") private var responseTime = "Fast"
    @AppStorage("microphoneGainOffset") private var microphoneGainOffset = 0.0
    @AppStorage("noiseAlertEnabled") private var noiseAlertEnabled = false
    @AppStorage("noiseAlertThreshold") private var noiseAlertThreshold = -12.0
    @AppStorage("showMeasurementDisclaimer") private var showDisclaimer = true
    @State private var showingProPaywall = false
    @State private var showingOnboarding = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingProPaywall = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "crown.fill")
                                .font(.title2)
                                .foregroundStyle(Color.yellow)
                                .padding(10)
                                .background(Color.yellow.opacity(0.15), in: Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text("SoundMeter Pro")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("PRO")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppTheme.accent, in: Capsule())
                                }

                                Text("Unlock A/C weighting, PDF reports & cloud sync")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }

                Section("Measurement") {
                    Picker("Frequency weighting", selection: $weighting) {
                        ForEach(FrequencyWeighting.allCases) { w in
                            Text(w.displayName).tag(w.rawValue)
                        }
                    }
                    if let selected = FrequencyWeighting(rawValue: weighting) {
                        Text(selected.descriptionText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Response time", selection: $responseTime) {
                        Text("Fast — 200 ms").tag("Fast")
                        Text("Slow — 500 ms").tag("Slow")
                        Text("Impulse — 50 ms").tag("Impulse")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Microphone gain offset", value: String(format: "%+.1f dB", microphoneGainOffset))
                        Slider(value: $microphoneGainOffset, in: -20...20, step: 0.5)
                        Text("Use this only after comparing against a known reference meter. It adjusts the displayed dBFS estimate; it does not certify SPL accuracy.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    NavigationLink("Calibration profiles") {
                        CalibrationView()
                    }
                }

                Section("Privacy & Accuracy") {
                    Toggle("Show measurement disclaimer", isOn: $showDisclaimer)
                    Text("Microphone samples are processed locally by this starter. Absolute sound pressure level requires validated calibration.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("Apple AVFoundation documentation", destination: URL(string: "https://developer.apple.com/documentation/avfoundation")!)
                }

                Section("Loud-noise alert") {
                    Toggle("Alert when threshold is exceeded", isOn: $noiseAlertEnabled)
                    if noiseAlertEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Threshold", value: String(format: "%.1f dBFS", noiseAlertThreshold))
                            Slider(value: $noiseAlertThreshold, in: -60 ... -1, step: 1)
                            Text("Alerts run while an active measurement is open. They are based on the adjusted dBFS estimate, not a certified SPL threshold.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Help & Guides") {
                    Button {
                        showingOnboarding = true
                    } label: {
                        HStack {
                            Label("Review Onboarding Guide", systemImage: "sparkles")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "0.2.0")
                    LabeledContent("Minimum iOS", value: "17.0")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingProPaywall) {
                NavigationStack {
                    ProView()
                }
            }
            .sheet(isPresented: $showingOnboarding) {
                OnboardingView(isReviewMode: true)
            }
        }
    }
}

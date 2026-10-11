import SwiftUI
import SwiftData

struct CalibrationView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CalibrationProfile.updatedAt, order: .reverse)
    private var profiles: [CalibrationProfile]

    @AppStorage("microphoneGainOffset") private var microphoneGainOffset = 0.0

    @State private var name = "My iPhone"
    @State private var offset = 0.0
    @State private var showingSaved = false

    // Reference calibrator calculator fields
    @State private var referenceDBText = "94.0"
    @State private var measuredDBText = ""
    @State private var showingCalculatorAlert = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Active Gain Offset")
                            .font(.headline)
                        Spacer()
                        Text(String(format: "%+.1f dB", offset))
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(Color(red: 0.98, green: 0.44, blue: 0.16))
                    }

                    Slider(value: $offset, in: -20...20, step: 0.5)
                        .tint(Color(red: 0.98, green: 0.44, blue: 0.16))
                        .onChange(of: offset) { _, newValue in
                            microphoneGainOffset = newValue
                        }

                    HStack {
                        Text("-20 dB")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text("0 dB (Default)")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text("+20 dB")
                            .font(.caption2).foregroundStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        offset = 0.0
                        microphoneGainOffset = 0.0
                    } label: {
                        Label("Reset Offset to 0.0 dB", systemImage: "arrow.counterclockwise")
                            .font(.subheadline)
                    }
                    .padding(.top, 4)

                    Text("An offset adjusts the displayed sound level estimate relative to a reference meter. It does not certify laboratory SPL compliance.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Microphone Calibration")
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("If you possess an external acoustic calibrator (e.g. 94.0 dB SPL at 1 kHz), enter the reference value and current uncalibrated reading below:")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("Reference SPL")
                        Spacer()
                        TextField("94.0", text: $referenceDBText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("dB")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Device Reading")
                        Spacer()
                        TextField("e.g. 91.5", text: $measuredDBText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("dB")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        calculateOffsetFromReference()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Calculate & Apply Offset")
                                .bold()
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.98, green: 0.44, blue: 0.16))
                }
            } header: {
                Text("Reference Calibrator Wizard")
            }

            Section {
                TextField("Profile name", text: $name)
                Button("Save as New Profile") {
                    let profile = CalibrationProfile(name: name.isEmpty ? "Calibration" : name, offsetDB: offset)
                    context.insert(profile)
                    try? context.save()
                    showingSaved = true
                }
            } header: {
                Text("Save Profile")
            }

            Section {
                if profiles.isEmpty {
                    Text("No saved profiles").foregroundStyle(.secondary)
                } else {
                    ForEach(profiles) { profile in
                        Button {
                            name = profile.name
                            offset = profile.offsetDB
                            microphoneGainOffset = profile.offsetDB
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.name)
                                        .font(.body.weight(profile.offsetDB == offset ? .bold : .regular))
                                        .foregroundStyle(.primary)
                                    Text(profile.updatedAt, format: .dateTime.month().day().year())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if abs(profile.offsetDB - offset) < 0.01 {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color(red: 0.98, green: 0.44, blue: 0.16))
                                }
                                Text(String(format: "%+.1f dB", profile.offsetDB))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(profiles[index]) }
                        try? context.save()
                    }
                }
            } header: {
                Text("Saved Profiles")
            } footer: {
                Text("Tap any profile to activate its offset in real-time.")
            }
        }
        .navigationTitle("Calibration")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .onAppear {
            offset = microphoneGainOffset
        }
        .alert("Profile Saved", isPresented: $showingSaved) {
            Button("OK", role: .cancel) {}
        }
    }

    private func calculateOffsetFromReference() {
        guard let ref = Double(referenceDBText.replacingOccurrences(of: ",", with: ".")),
              let measured = Double(measuredDBText.replacingOccurrences(of: ",", with: ".")) else {
            return
        }
        let calculated = (ref - measured).clamped(to: -20.0...20.0)
        let rounded = (calculated * 2.0).rounded() / 2.0
        offset = rounded
        microphoneGainOffset = rounded
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

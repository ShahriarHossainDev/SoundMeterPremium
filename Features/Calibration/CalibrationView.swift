import SwiftUI
import SwiftData

struct CalibrationView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CalibrationProfile.updatedAt, order: .reverse)
    private var profiles: [CalibrationProfile]
    @State private var name = "My iPhone"
    @State private var offset = 0.0
    @State private var showingSaved = false

    var body: some View {
        Form {
            Section("Calibration profile") {
                TextField("Profile name", text: $name)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Offset")
                        Spacer()
                        Text("\(offset, specifier: "%.1f") dB").monospacedDigit()
                    }
                    Slider(value: $offset, in: -20...20, step: 0.5)
                    Text("An offset is only a reference adjustment. It does not calibrate frequency response or make the phone a certified sound-level meter.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("Save Profile") {
                    context.insert(CalibrationProfile(name: name.isEmpty ? "Calibration" : name, offsetDB: offset))
                    try? context.save()
                    showingSaved = true
                }
            }

            Section("Saved profiles") {
                if profiles.isEmpty {
                    Text("No profiles saved").foregroundStyle(.secondary)
                } else {
                    ForEach(profiles) { profile in
                        Button {
                            name = profile.name
                            offset = profile.offsetDB
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(profile.name).foregroundStyle(.primary)
                                    Text(profile.updatedAt, format: .dateTime.month().day().year())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(profile.offsetDB, specifier: "%.1f") dB")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(profiles[index]) }
                        try? context.save()
                    }
                }
            }
        }
        .navigationTitle("Calibration")
        .alert("Profile saved", isPresented: $showingSaved) {
            Button("OK", role: .cancel) {}
        }
    }
}

import SwiftUI
import SwiftData

struct MeterView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var model = MeterViewModel()
    @State private var sessionTitle = "Sound Session"
    @State private var showingSave = false
    @AppStorage("noiseAlertEnabled") private var noiseAlertEnabled = false
    @AppStorage("noiseAlertThreshold") private var noiseAlertThreshold = -12.0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sound Meter").font(.largeTitle.bold())
                        Text("Your real-time sound companion").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    NavigationLink {
                        SpectrumView()
                    } label: {
                        Image(systemName: "waveform.path")
                            .font(.title3.bold())
                            .foregroundStyle(AppTheme.secondaryAccent)
                            .padding(13)
                            .background(AppTheme.secondaryAccent.opacity(0.12), in: Circle())
                    }
                    Image(systemName: "waveform").font(.title2.bold())
                        .foregroundStyle(AppTheme.accent)
                        .padding(13)
                        .background(AppTheme.accent.opacity(0.12), in: Circle())
                }

                ZStack {
                    Circle().stroke(Color.primary.opacity(0.06), lineWidth: 16)
                    Circle()
                        .trim(from: 0, to: gaugeProgress)
                        .stroke(
                            AngularGradient(colors: [AppTheme.accent, AppTheme.secondaryAccent], center: .center),
                            style: StrokeStyle(lineWidth: 16, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 5) {
                        Text(model.currentDBFS, format: .number.precision(.fractionLength(1)))
                            .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                            .minimumScaleFactor(0.6).lineLimit(1)
                        Text(model.unitSymbol).font(.headline).foregroundStyle(.secondary)
                        Text(stateTitle).font(.caption.weight(.semibold)).foregroundStyle(model.state == .measuring ? AppTheme.accent : .secondary)
                    }.padding(30)
                }
                .frame(width: 250, height: 250)
                .padding(.vertical, 2)

                // Frequency Weighting Filter Selector
                VStack(spacing: 6) {
                    Picker("Frequency Weighting", selection: $model.weighting) {
                        ForEach(FrequencyWeighting.allCases) { w in
                            Text(w.rawValue).tag(w)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)

                    Text(model.weighting.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if noiseAlertEnabled {
                    Label("Alert at \(noiseAlertThreshold, format: .number.precision(.fractionLength(1))) \(model.unitSymbol)", systemImage: model.currentDBFS >= noiseAlertThreshold ? "exclamationmark.triangle.fill" : "bell.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(model.currentDBFS >= noiseAlertThreshold ? .orange : .secondary)
                }

                HStack(spacing: 10) {
                    MeterStat(title: "Average", value: model.averageDBFS, unit: model.unitSymbol)
                    MeterStat(title: "Maximum", value: model.maximumDBFS, unit: model.unitSymbol)
                    MeterStat(title: "Minimum", value: model.minimumDBFS, unit: model.unitSymbol)
                }

                PremiumCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Live trend").font(.headline)
                            Spacer()
                            Text(formatTime(model.elapsed)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        LevelLineChart(values: model.graphSamples)
                            .frame(height: 88)
                    }
                }

                controlPanel

                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingSave) {
            NavigationStack {
                Form {
                    Section("Session") {
                        TextField("Session name", text: $sessionTitle)
                    }
                    Section {
                        LabeledContent("Duration", value: formatTime(model.elapsed))
                        LabeledContent("Weighting", value: model.weighting.displayName)
                        LabeledContent("Average", value: "\(model.averageDBFS, default: "%.1f") \(model.unitSymbol)")
                        LabeledContent("Peak", value: "\(model.maximumDBFS, default: "%.1f") \(model.unitSymbol)")
                    }
                }
                .navigationTitle("Save Measurement")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingSave = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            model.save(context: context, title: sessionTitle)
                            sessionTitle = "Sound Session"
                            showingSave = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    @ViewBuilder private var controlPanel: some View {
        switch model.state {
        case .idle, .failed:
            PrimaryActionButton(title: "Start Measurement", systemImage: "mic.fill") { model.start() }
        case .starting:
            ProgressView("Starting microphone…").frame(maxWidth: .infinity).padding()
        case .measuring:
            HStack(spacing: 12) {
                Button { model.pause() } label: {
                    Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity).padding(.vertical, 13)
                }.buttonStyle(.bordered)
                Button(role: .destructive) { model.stop() } label: {
                    Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity).padding(.vertical, 13)
                }.buttonStyle(.bordered)
            }
        case .paused:
            HStack(spacing: 12) {
                Button { model.start() } label: {
                    Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 13)
                }.buttonStyle(.borderedProminent).tint(AppTheme.accent).foregroundStyle(.black)
                Button(role: .destructive) { model.stop() } label: {
                    Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity).padding(.vertical, 13)
                }.buttonStyle(.bordered)
            }
        case .stopped:
            VStack(spacing: 10) {
                PrimaryActionButton(title: "Save Session", systemImage: "square.and.arrow.down") { showingSave = true }
                Button("Discard and reset", role: .destructive) { model.reset() }
            }
        }
    }

    private var gaugeProgress: CGFloat {
        CGFloat(min(max((model.currentDBFS + 120) / 120, 0), 1))
    }

    private var stateTitle: String {
        switch model.state {
        case .idle: "READY"
        case .starting: "STARTING"
        case .measuring: "MEASURING"
        case .paused: "PAUSED"
        case .stopped: "STOPPED"
        case .failed: "UNAVAILABLE"
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

private struct MeterStat: View {
    let title: String
    let value: Double
    var unit: String = "dBFS"

    var body: some View {
        PremiumCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value, format: .number.precision(.fractionLength(1)))
                    .font(.system(.title3, design: .rounded).bold().monospacedDigit())
                    .minimumScaleFactor(0.65).lineLimit(1)
                Text(unit).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

private struct LevelLineChart: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(1..<4, id: \.self) { row in
                    Path { path in
                        let y = geometry.size.height * CGFloat(row) / 4
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }.stroke(Color.primary.opacity(0.07), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                Path { path in
                    guard values.count > 1 else { return }
                    for index in values.indices {
                        let x = CGFloat(index) / CGFloat(max(values.count - 1, 1)) * geometry.size.width
                        let normalized = (values[index] + 120) / 120
                        let y = geometry.size.height * (1 - CGFloat(min(max(normalized, 0), 1)))
                        if index == values.startIndex { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

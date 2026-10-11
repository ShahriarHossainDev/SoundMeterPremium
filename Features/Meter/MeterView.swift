import SwiftUI
import SwiftData

struct MeterView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var model = MeterViewModel()

    @State private var showingSave = false
    @State private var sessionTitle = "Sound Session"
    @State private var showingProPaywall = false
    @State private var showingCalibration = false
    @State private var showingReports = false
    @State private var showingInfo = false
    @State private var showingResetAlert = false
    @State private var isFullScreenSpectrum = false

    @AppStorage("noiseAlertEnabled") private var noiseAlertEnabled = false
    @AppStorage("noiseAlertThreshold") private var noiseAlertThreshold = -12.0
    @AppStorage("showSpectrumPeaks") private var showSpectrumPeaks = true

    // Theme tokens matching screenshot
    private let darkBackground = Color(red: 0.04, green: 0.06, blue: 0.09) // #0A0F17
    private let cardBackground = Color(red: 0.07, green: 0.10, blue: 0.14) // #121A24
    private let accentBlue = Color(red: 0.22, green: 0.65, blue: 0.98)     // #38BDF8
    private let accentOrange = Color(red: 0.98, green: 0.44, blue: 0.16)   // #FA7028
    private let accentGreen = Color(red: 0.55, green: 0.88, blue: 0.25)    // #8CE040
    private let accentPink = Color(red: 0.94, green: 0.45, blue: 0.70)     // #F073B3

    var body: some View {
        ZStack(alignment: .top) {
            darkBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // 1. Top Audio Level Segmented LED Bar
                topAudioMeterBar
                    .padding(.top, 4)
                    .padding(.bottom, 6)

                if isFullScreenSpectrum {
                    // Fullscreen active chart mode
                    spectrumSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 10)
                        .padding(.bottom, 96)
                        .transition(.opacity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 12) {
                            // 2. Visualization Chart Section
                            spectrumSection
                                .frame(height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .padding(.horizontal, 14)

                            // 3. Action Toolbar (Clipboard, Mode, Upgrade, Target, Trend)
                            actionToolbar
                                .padding(.horizontal, 14)
                                .padding(.vertical, 2)

                            // 4. Analog Sound Meter Panel
                            analogMeterCard
                                .padding(.horizontal, 14)

                            // 5. Live Measurement Stats Bottom Card
                            liveMeasurementStatsCard
                                .padding(.horizontal, 14)
                                .padding(.bottom, 96) // Space for floating bottom tab bar
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            model.reloadConfiguration()
            model.start()
        }
        .sheet(isPresented: $showingSave) {
            saveSessionSheet
        }
        .sheet(isPresented: $showingProPaywall) {
            NavigationStack {
                ProView()
            }
        }
        .sheet(isPresented: $showingCalibration) {
            NavigationStack {
                CalibrationView()
            }
        }
        .sheet(isPresented: $showingReports) {
            ReportsView()
        }
        .sheet(isPresented: $showingInfo) {
            spectrumInfoSheet
        }
        .alert("Reset Measurements?", isPresented: $showingResetAlert) {
            Button("Reset", role: .destructive) {
                model.reset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear current average, minimum, and maximum session statistics.")
        }
    }

    // MARK: - 1. Top Segmented Audio Level Bar
    private var topAudioMeterBar: some View {
        HStack(spacing: 3) {
            let totalSegments = 28
            let activeSegments = Int(round(model.audioMeterFraction * Double(totalSegments)))

            ForEach(0..<totalSegments, id: \.self) { index in
                let segColor: Color = {
                    if index < 18 {
                        return accentGreen
                    } else if index < 24 {
                        return accentOrange
                    } else {
                        return Color(red: 0.95, green: 0.22, blue: 0.22)
                    }
                }()

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < activeSegments ? segColor : Color(white: 0.13))
                    .frame(height: 7)
                    .shadow(color: index < activeSegments ? segColor.opacity(0.55) : .clear, radius: 2)
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: - 2. Visualization Chart Section (Supports All 5 Modes)
    private var spectrumSection: some View {
        ZStack(alignment: .top) {
            Color.black

            // Active Visualization Mode Canvas
            Group {
                switch model.visualizationMode {
                case .spectrumBars:
                    SpectrumBarsCanvas(
                        curveData: model.spectrumCurveData,
                        selectedFrequency: model.displayedFrequency,
                        weightingUnit: model.unitSymbol,
                        showPeaks: showSpectrumPeaks
                    )
                case .spectrumLine:
                    SpectrumLineCanvas(
                        curveData: model.spectrumCurveData,
                        selectedFrequency: model.displayedFrequency,
                        weightingUnit: model.unitSymbol,
                        showPeaks: showSpectrumPeaks
                    )
                case .waveform:
                    WaveformTrendCanvas(
                        samples: model.waveformSamples,
                        currentDB: model.estimatedCurrentDB,
                        weightingUnit: model.unitSymbol
                    )
                case .historyGraph:
                    HistoryGraphCanvas(
                        samples: model.graphSamples,
                        minDB: model.estimatedMinimumDB,
                        maxDB: model.estimatedMaximumDB,
                        avgDB: model.estimatedAverageDB,
                        weightingUnit: model.unitSymbol
                    )
                case .spectrogram:
                    SpectrogramCanvas(
                        history: model.spectrogramHistory,
                        weightingUnit: model.unitSymbol
                    )
                }
            }
            .animation(.easeInOut(duration: 0.25), value: model.visualizationMode)

            // Overlaid Spectrum HUD Controls
            VStack {
                // Top Row Controls
                HStack(alignment: .center, spacing: 6) {
                    // Info button
                    Button {
                        showingInfo = true
                    } label: {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }

                    // Profile selector pill
                    Button {
                        model.cycleEnvironmentProfile()
                    } label: {
                        VStack(spacing: 2) {
                            HStack(spacing: 3) {
                                ForEach(EnvironmentProfile.allCases) { profile in
                                    Circle()
                                        .fill(profile == model.environmentProfile ? Color.white : Color.white.opacity(0.25))
                                        .frame(width: 3.5, height: 3.5)
                                }
                            }
                            Text(model.environmentProfile.rawValue)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.14), in: Capsule())
                    }

                    // Mode Selector Menu Pill
                    Menu {
                        ForEach(MeterVisualizationMode.allCases) { mode in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    model.visualizationMode = mode
                                }
                            } label: {
                                Label(mode.title, systemImage: mode.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: model.visualizationMode.icon)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(accentOrange)
                            Text(model.visualizationMode.rawValue)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.14), in: Capsule())
                    }

                    Spacer()

                    // Noise Alert Toggle
                    Button {
                        noiseAlertEnabled.toggle()
                    } label: {
                        Image(systemName: noiseAlertEnabled ? "bell.fill" : "bell.slash.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(noiseAlertEnabled ? accentOrange : Color.white.opacity(0.85))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }

                    // Fullscreen Toggle
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isFullScreenSpectrum.toggle()
                        }
                    } label: {
                        Image(systemName: isFullScreenSpectrum ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)

                Spacer()

                // Bottom frequency / mode stepping row
                HStack {
                    Button {
                        if model.visualizationMode == .spectrumBars || model.visualizationMode == .spectrumLine {
                            model.selectPreviousFrequency()
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                model.previousVisualizationMode()
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }

                    Spacer()

                    if model.visualizationMode == .spectrumBars || model.visualizationMode == .spectrumLine {
                        Text(String(format: "%.0f Hz", model.displayedFrequency))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(accentGreen)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.65), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    }

                    Spacer()

                    Button {
                        if model.visualizationMode == .spectrumBars || model.visualizationMode == .spectrumLine {
                            model.selectNextFrequency()
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                model.nextVisualizationMode()
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - 3. Action Toolbar (Evenly Distributed Toolbar Items)
    private var actionToolbar: some View {
        HStack(spacing: 0) {
            // 1. Clipboard / Reports button
            Button {
                showingReports = true
            } label: {
                Image(systemName: "doc.plaintext")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(cardBackground, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            }

            Spacer()

            // 2. Visualization Mode action button
            Menu {
                ForEach(MeterVisualizationMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            model.visualizationMode = mode
                        }
                    } label: {
                        Label(mode.title, systemImage: mode.icon)
                    }
                }
            } label: {
                Image(systemName: model.visualizationMode.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accentOrange)
                    .frame(width: 44, height: 44)
                    .background(cardBackground, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            } primaryAction: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.cycleVisualizationMode()
                }
            }

            Spacer()

            // 3. Centered Orange Upgrade Button
            Button {
                showingProPaywall = true
            } label: {
                Text("Upgrade")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 11)
                    .background(
                        LinearGradient(
                            colors: [accentOrange, Color(red: 1.0, green: 0.32, blue: 0.10)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: Capsule()
                    )
                    .shadow(color: accentOrange.opacity(0.35), radius: 6, y: 2)
            }

            Spacer()

            // 4. Target / Calibration button
            Button {
                showingCalibration = true
            } label: {
                Image(systemName: "scope")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(cardBackground, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            }

            Spacer()

            // 5. History / Trend button
            NavigationLink {
                HistoryView()
            } label: {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(cardBackground, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
        }
    }

    // MARK: - 4. Analog Sound Meter Card
    private var analogMeterCard: some View {
        VStack(spacing: 0) {
            // Semicircular Analog Gauge Dial
            AnalogGaugeDial(
                level: model.estimatedCurrentDB,
                minLevel: model.estimatedMinimumDB,
                maxLevel: model.estimatedMaximumDB
            )
            .frame(height: 175)

            // Bottom Controls Row: Reset, Pause/Resume with Duration, Save
            HStack(alignment: .center) {
                // Reset Button
                Button {
                    if model.state == .measuring || model.state == .paused {
                        showingResetAlert = true
                    } else {
                        model.reset()
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.10), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }

                Spacer()

                // Central Large Pause/Resume Button + Elapsed Time
                VStack(spacing: 5) {
                    Button {
                        model.togglePauseResume()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(Color(red: 0.98, green: 0.78, blue: 0.28), lineWidth: 2.5)
                                .frame(width: 62, height: 62)

                            Circle()
                                .fill(Color(red: 0.08, green: 0.11, blue: 0.16))
                                .frame(width: 57, height: 57)

                            Image(systemName: model.state == .measuring ? "pause.fill" : "play.fill")
                                .font(.system(size: 21, weight: .bold))
                                .foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.28))
                        }
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 9, weight: .semibold))
                        Text(model.elapsedFormatted)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(Color.white.opacity(0.55))
                }

                Spacer()

                // Save / Export Button
                Button {
                    showingSave = true
                } label: {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.10), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - 5. Live Measurement Stats Bottom Card
    private var liveMeasurementStatsCard: some View {
        HStack(alignment: .center) {
            // LEFT: AVG
            VStack(spacing: 4) {
                Text("AVG")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08), in: Capsule())

                Text(model.estimatedAverageDB > 0 ? String(format: "%.1f", model.estimatedAverageDB) : "--")
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accentBlue)
            }
            .frame(maxWidth: .infinity)

            // CENTER: Large Live Measurement & Weighting Unit
            VStack(spacing: 4) {
                Text(model.estimatedCurrentDB > 0 ? String(format: "%.1f", model.estimatedCurrentDB) : "--")
                    .font(.system(size: 54, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accentOrange)

                Button {
                    cycleWeighting()
                } label: {
                    HStack(spacing: 3) {
                        Text(model.unitSymbol)
                            .font(.system(size: 11, weight: .bold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.12), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)

            // RIGHT: MAX
            VStack(spacing: 4) {
                Text("MAX")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08), in: Capsule())

                Text(model.estimatedMaximumDB > 0 ? String(format: "%.1f", model.estimatedMaximumDB) : "--")
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accentBlue)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Helpers
    private func cycleWeighting() {
        switch model.weighting {
        case .z: model.setWeighting(.a)
        case .a: model.setWeighting(.c)
        case .c: model.setWeighting(.z)
        }
    }

    // MARK: - Save Session Modal
    private var saveSessionSheet: some View {
        NavigationStack {
            Form {
                Section("Session Information") {
                    TextField("Session Name", text: $sessionTitle)
                }

                Section("Measurement Summary") {
                    LabeledContent("Duration", value: model.elapsedFormatted)
                    LabeledContent("Weighting", value: model.weighting.displayName)
                    LabeledContent("Average Level", value: String(format: "%.1f %@", model.estimatedAverageDB, model.unitSymbol))
                    LabeledContent("Peak Level", value: String(format: "%.1f %@", model.estimatedMaximumDB, model.unitSymbol))
                    LabeledContent("Minimum Level", value: String(format: "%.1f %@", model.estimatedMinimumDB, model.unitSymbol))
                }
            }
            .navigationTitle("Save Session")
            .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Spectrum Info Modal
    private var spectrumInfoSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Meter Visualization Modes", systemImage: "waveform.path")
                        .font(.title2.bold())
                        .foregroundStyle(accentOrange)

                    Text("SoundMeter Premium provides five specialized acoustic visualization modes driven directly by real-time audio captured from your microphone and processed with Apple's Accelerate framework.")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Divider()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Five Visualization Engines").font(.headline)

                        // Mode 1: Spectrum Bars
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(accentGreen)
                                .frame(width: 20)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("1. Spectrum Bars")
                                    .font(.subheadline.bold())
                                Text("Vertical lime-green frequency bars with pink peak-hold caps across logarithmic frequency bands (20 Hz to 20,000 Hz).")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }

                        // Mode 2: Spectrum Line
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(accentGreen)
                                .frame(width: 20)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("2. Spectrum Line")
                                    .font(.subheadline.bold())
                                Text("Dual continuous FFT curves: lime-green instantaneous acoustic energy and pink peak-hold envelope.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }

                        // Mode 3: Waveform / Live Trend
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "waveform")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(accentGreen)
                                .frame(width: 20)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("3. Live Waveform Trend")
                                    .font(.subheadline.bold())
                                Text("High-resolution real-time scrolling acoustic decibel trend with glowing leading edge and area illumination.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }

                        // Mode 4: History Graph
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(accentBlue)
                                .frame(width: 20)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("4. Session History Graph")
                                    .font(.subheadline.bold())
                                Text("Chronological time-domain curve showing session progression with calibrated MIN (blue), MAX (orange), and AVG guideline markers.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }

                        // Mode 5: Spectrogram
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "square.grid.3x3.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.cyan)
                                .frame(width: 20)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("5. Waterfall Spectrogram")
                                    .font(.subheadline.bold())
                                Text("Two-dimensional time-versus-frequency acoustic heatmap mapping energy distribution using Deep Navy, Cyan, Lime Green, Yellow, and Red spectrum colors.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Acoustic Measurement Disclosure").font(.headline)
                        Text("iOS device microphones measure digital sound levels (dBFS). Displayed readings estimate equivalent sound pressure levels referenced to digital full scale. For certified environmental noise surveys or regulatory compliance, an external calibrated acoustic reference meter must be used.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Visualization Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingInfo = false }
                }
            }
        }
    }
}


// MARK: - Mode 1: Spectrum Bars Canvas
private struct SpectrumBarsCanvas: View {
    let curveData: SpectrumCurveData?
    let selectedFrequency: Double
    let weightingUnit: String
    var showPeaks: Bool = true

    private let gridColor = Color(red: 0.16, green: 0.22, blue: 0.30)
    private let barColor = Color(red: 0.55, green: 0.88, blue: 0.25) // Lime green
    private let peakColor = Color(red: 0.94, green: 0.45, blue: 0.70) // Pink

    private let frequencyLabels: [(name: String, freq: Double)] = [
        ("500", 500.0),
        ("1K", 1000.0),
        ("2K", 2000.0),
        ("4K", 4000.0),
        ("8K", 8000.0),
        ("16K", 16000.0)
    ]
    private let dbMarkers: [Int] = [120, 100, 80, 60, 40, 20, 0, -20]

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                // 1. Horizontal dB Grid Lines & Scale Markers
                for db in dbMarkers {
                    let y = yForDB(Double(db), height: size.height)
                    var line = Path()
                    line.move(to: CGPoint(x: 32, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(line, with: .color(gridColor), lineWidth: 0.8)

                    let labelText = db == 20 ? "20 \(weightingUnit)" : "\(db)"
                    let text = Text(labelText)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.4))
                    ctx.draw(text, at: CGPoint(x: 18, y: y), anchor: .center)
                }

                // 2. Vertical Frequency Grid Lines & Top Labels
                for mark in frequencyLabels {
                    let x = xForFreq(mark.freq, width: size.width)
                    var vLine = Path()
                    vLine.move(to: CGPoint(x: x, y: 16))
                    vLine.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(vLine, with: .color(gridColor), lineWidth: 0.8)

                    let text = Text(mark.name)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.45))
                    ctx.draw(text, at: CGPoint(x: x, y: 8), anchor: .center)
                }

                // 3. Draw Vertical Spectrum Bars with Peak Hold Caps
                if let data = curveData, data.frequencies.count > 1 {
                    let totalBars = 36
                    let leftMargin: CGFloat = 36
                    let usableWidth = size.width - leftMargin - 8
                    let slotWidth = usableWidth / CGFloat(totalBars)
                    let barWidth = max(3.0, slotWidth - 2.5)
                    let baselineY = yForDB(-20.0, height: size.height)

                    var peakBarX: CGFloat = 0
                    var peakBarY: CGFloat = size.height

                    for b in 0..<totalBars {
                        let sampleIdx = Int(round(Double(b) * Double(data.frequencies.count - 1) / Double(totalBars - 1)))
                        let f = data.frequencies[sampleIdx]
                        let instDB = data.instantaneousDB[sampleIdx]
                        let peakDB = data.peakHoldDB[sampleIdx]

                        let x = leftMargin + CGFloat(b) * slotWidth + (slotWidth - barWidth) / 2
                        let instY = yForDB(instDB, height: size.height)
                        let barHeight = max(2.0, baselineY - instY)

                        // Draw Lime Green Bar
                        let barRect = CGRect(x: x, y: instY, width: barWidth, height: barHeight)
                        let barPath = Path(roundedRect: barRect, cornerRadius: 1.5)
                        ctx.fill(barPath, with: .color(barColor))

                        if showPeaks {
                            // Draw Pink Peak Hold Cap
                            let peakY = yForDB(peakDB, height: size.height)
                            let capRect = CGRect(x: x, y: peakY - 1.5, width: barWidth, height: 2.5)
                            ctx.fill(Path(roundedRect: capRect, cornerRadius: 1.0), with: .color(peakColor))
                        }

                        if abs(f - selectedFrequency) < (usableWidth / Double(totalBars) * 20.0) {
                            peakBarX = x + barWidth / 2
                            peakBarY = yForDB(peakDB, height: size.height)
                        }
                    }

                    if showPeaks {
                        // Floating Dominant / Selected Frequency Callout
                        let calloutX = peakBarX > 0 ? peakBarX : xForFreq(selectedFrequency, width: size.width)
                        let calloutY = peakBarY < size.height ? peakBarY : yForDB(data.peakLevelDB, height: size.height)
                        let callout = Text(String(format: "%.0f Hz", selectedFrequency))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        ctx.draw(callout, at: CGPoint(x: min(size.width - 45, max(45, calloutX)), y: max(22, calloutY - 14)), anchor: .center)
                    }
                }
            }
        }
    }

    private func xForFreq(_ freq: Double, width: CGFloat) -> CGFloat {
        let minF = 20.0
        let maxF = 20000.0
        let clamped = max(minF, min(maxF, freq))
        let logMin = log(minF)
        let logMax = log(maxF)
        let norm = (log(clamped) - logMin) / (logMax - logMin)
        return 36 + CGFloat(norm) * (width - 44)
    }

    private func yForDB(_ db: Double, height: CGFloat) -> CGFloat {
        let minDB = -20.0
        let maxDB = 120.0
        let clamped = max(minDB, min(maxDB, db))
        let norm = (clamped - minDB) / (maxDB - minDB)
        return height - (CGFloat(norm) * (height - 18) + 8)
    }
}

// MARK: - Mode 2: Spectrum Line Canvas
private struct SpectrumLineCanvas: View {
    let curveData: SpectrumCurveData?
    let selectedFrequency: Double
    let weightingUnit: String
    var showPeaks: Bool = true

    private let gridColor = Color(red: 0.16, green: 0.22, blue: 0.30)
    private let pinkColor = Color(red: 0.94, green: 0.45, blue: 0.70)
    private let greenColor = Color(red: 0.55, green: 0.88, blue: 0.25)

    private let frequencyLabels: [(name: String, freq: Double)] = [
        ("500", 500.0),
        ("1K", 1000.0),
        ("2K", 2000.0),
        ("4K", 4000.0),
        ("8K", 8000.0),
        ("16K", 16000.0)
    ]
    private let dbMarkers: [Int] = [120, 100, 80, 60, 40, 20, 0, -20]

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                // 1. Draw Grid Lines & Scale Markers
                for db in dbMarkers {
                    let y = yForDB(Double(db), height: size.height)
                    var line = Path()
                    line.move(to: CGPoint(x: 32, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(line, with: .color(gridColor), lineWidth: 0.8)

                    let labelText = db == 20 ? "20 \(weightingUnit)" : "\(db)"
                    let text = Text(labelText)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.4))
                    ctx.draw(text, at: CGPoint(x: 18, y: y), anchor: .center)
                }

                // Vertical Frequency Grid Lines & Top Labels
                for mark in frequencyLabels {
                    let x = xForFreq(mark.freq, width: size.width)
                    var vLine = Path()
                    vLine.move(to: CGPoint(x: x, y: 16))
                    vLine.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(vLine, with: .color(gridColor), lineWidth: 0.8)

                    let text = Text(mark.name)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.45))
                    ctx.draw(text, at: CGPoint(x: x, y: 8), anchor: .center)
                }

                // 2. Draw Spectrum Curves
                if let data = curveData, data.frequencies.count > 1 {
                    let count = data.frequencies.count

                    // Draw Lime Green Instantaneous Curve
                    var greenPath = Path()
                    for i in 0..<count {
                        let x = xForFreq(data.frequencies[i], width: size.width)
                        let y = yForDB(data.instantaneousDB[i], height: size.height)
                        if i == 0 {
                            greenPath.move(to: CGPoint(x: x, y: y))
                        } else {
                            greenPath.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    ctx.stroke(greenPath, with: .color(greenColor), lineWidth: 1.5)

                    if showPeaks {
                        // Draw Pink Peak Hold Curve
                        var pinkPath = Path()
                        for i in 0..<count {
                            let x = xForFreq(data.frequencies[i], width: size.width)
                            let y = yForDB(data.peakHoldDB[i], height: size.height)
                            if i == 0 {
                                pinkPath.move(to: CGPoint(x: x, y: y))
                            } else {
                                pinkPath.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        ctx.stroke(pinkPath, with: .color(pinkColor), lineWidth: 1.6)

                        // Draw Selected / Peak Frequency Callout
                        var curveLevel = data.peakLevelDB
                        if let closestIndex = data.frequencies.indices.min(by: { abs(data.frequencies[$0] - selectedFrequency) < abs(data.frequencies[$1] - selectedFrequency) }) {
                            curveLevel = max(data.instantaneousDB[closestIndex], data.peakHoldDB[closestIndex])
                        }
                        let peakX = xForFreq(selectedFrequency, width: size.width)
                        let peakY = yForDB(curveLevel, height: size.height)

                        let callout = Text(String(format: "%.0f Hz", selectedFrequency))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        ctx.draw(callout, at: CGPoint(x: min(size.width - 45, max(45, peakX)), y: max(22, peakY - 14)), anchor: .center)
                    }
                }
            }
        }
    }

    private func xForFreq(_ freq: Double, width: CGFloat) -> CGFloat {
        let minF = 20.0
        let maxF = 20000.0
        let clamped = max(minF, min(maxF, freq))
        let logMin = log(minF)
        let logMax = log(maxF)
        let norm = (log(clamped) - logMin) / (logMax - logMin)
        let usableWidth = width - 36
        return 36 + CGFloat(norm) * usableWidth
    }

    private func yForDB(_ db: Double, height: CGFloat) -> CGFloat {
        let minDB = -20.0
        let maxDB = 120.0
        let clamped = max(minDB, min(maxDB, db))
        let norm = (clamped - minDB) / (maxDB - minDB)
        return height - (CGFloat(norm) * (height - 18) + 8)
    }
}

// MARK: - Mode 3: Waveform / Live Trend Canvas
private struct WaveformTrendCanvas: View {
    let samples: [Double]
    let currentDB: Double
    let weightingUnit: String

    private let gridColor = Color(red: 0.16, green: 0.22, blue: 0.30)
    private let lineColor = Color(red: 0.55, green: 0.88, blue: 0.25) // Lime green
    private let dbMarkers: [Int] = [120, 100, 80, 60, 40, 20]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                Canvas { ctx, size in
                    // Horizontal dB grid lines
                    for db in dbMarkers {
                        let y = yForDB(Double(db), height: size.height)
                        var line = Path()
                        line.move(to: CGPoint(x: 32, y: y))
                        line.addLine(to: CGPoint(x: size.width, y: y))
                        ctx.stroke(line, with: .color(gridColor), lineWidth: 0.8)

                        let labelText = db == 20 ? "20 \(weightingUnit)" : "\(db)"
                        let text = Text(labelText)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.4))
                        ctx.draw(text, at: CGPoint(x: 18, y: y), anchor: .center)
                    }

                    // Vertical Time Divisions (every 25% of width)
                    for frac in [0.25, 0.50, 0.75] {
                        let x = 32 + CGFloat(frac) * (size.width - 32)
                        var vLine = Path()
                        vLine.move(to: CGPoint(x: x, y: 16))
                        vLine.addLine(to: CGPoint(x: x, y: size.height))
                        ctx.stroke(vLine, with: .color(gridColor.opacity(0.6)), lineWidth: 0.6)
                    }

                    // Render Scrolling Waveform
                    guard samples.count > 1 else { return }
                    let leftMargin: CGFloat = 36
                    let usableWidth = size.width - leftMargin - 6
                    let stepX = usableWidth / CGFloat(max(1, samples.count - 1))

                    var path = Path()
                    var areaPath = Path()
                    let baselineY = yForDB(20.0, height: size.height)

                    for (i, sample) in samples.enumerated() {
                        let x = leftMargin + CGFloat(i) * stepX
                        let y = yForDB(sample, height: size.height)
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                            areaPath.move(to: CGPoint(x: x, y: baselineY))
                            areaPath.addLine(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                            areaPath.addLine(to: CGPoint(x: x, y: y))
                        }
                    }

                    if let last = samples.last {
                        let lastX = leftMargin + CGFloat(samples.count - 1) * stepX
                        areaPath.addLine(to: CGPoint(x: lastX, y: baselineY))
                        areaPath.closeSubpath()

                        // Shaded gradient fill
                        let gradient = Gradient(colors: [lineColor.opacity(0.22), lineColor.opacity(0.01)])
                        ctx.fill(areaPath, with: .linearGradient(gradient, startPoint: CGPoint(x: lastX, y: 0), endPoint: CGPoint(x: lastX, y: baselineY)))

                        // Stroke live green line
                        ctx.stroke(path, with: .color(lineColor), lineWidth: 2.0)

                        // Glowing leading dot at current reading
                        let dotY = yForDB(last, height: size.height)
                        let dotRect = CGRect(x: lastX - 4, y: dotY - 4, width: 8, height: 8)
                        ctx.fill(Path(ellipseIn: dotRect), with: .color(lineColor))
                    }
                }

                // Top right "LIVE" indicator badge
                HStack(spacing: 5) {
                    Circle()
                        .fill(lineColor)
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.6), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
                .padding(.trailing, 10)
                .padding(.top, 10)
            }
        }
    }

    private func yForDB(_ db: Double, height: CGFloat) -> CGFloat {
        let minDB = 20.0
        let maxDB = 130.0
        let clamped = max(minDB, min(maxDB, db))
        let norm = (clamped - minDB) / (maxDB - minDB)
        return height - (CGFloat(norm) * (height - 24) + 12)
    }
}

// MARK: - Mode 4: History Graph Canvas
private struct HistoryGraphCanvas: View {
    let samples: [Double]
    let minDB: Double
    let maxDB: Double
    let avgDB: Double
    let weightingUnit: String

    private let gridColor = Color(red: 0.16, green: 0.22, blue: 0.30)
    private let trendColor = Color(red: 0.22, green: 0.74, blue: 0.98) // Cyan blue
    private let minColor = Color(red: 0.22, green: 0.65, blue: 0.98) // Blue
    private let maxColor = Color(red: 0.98, green: 0.44, blue: 0.16) // Orange
    private let dbMarkers: [Int] = [120, 100, 80, 60, 40, 20]

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                // Horizontal dB grid lines
                for db in dbMarkers {
                    let y = yForDB(Double(db), height: size.height)
                    var line = Path()
                    line.move(to: CGPoint(x: 32, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(line, with: .color(gridColor), lineWidth: 0.8)

                    let labelText = db == 20 ? "20 \(weightingUnit)" : "\(db)"
                    let text = Text(labelText)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.4))
                    ctx.draw(text, at: CGPoint(x: 18, y: y), anchor: .center)
                }

                // Time labels across bottom
                let timeLabels = ["0s", "15s", "30s", "45s", "60s"]
                for (idx, tl) in timeLabels.enumerated() {
                    let frac = CGFloat(idx) / CGFloat(timeLabels.count - 1)
                    let x = 36 + frac * (size.width - 56)
                    let tText = Text(tl)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.4))
                    ctx.draw(tText, at: CGPoint(x: x, y: size.height - 6), anchor: .center)
                }

                // Min indicator line (blue dashed)
                if minDB > 20 {
                    let y = yForDB(minDB, height: size.height)
                    var minLine = Path()
                    minLine.move(to: CGPoint(x: 36, y: y))
                    minLine.addLine(to: CGPoint(x: size.width - 48, y: y))
                    ctx.stroke(minLine, with: .color(minColor.opacity(0.8)), style: StrokeStyle(lineWidth: 1.0, dash: [4, 4]))

                    let minBadge = Text(String(format: "MIN %.1f", minDB))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(minColor)
                    ctx.draw(minBadge, at: CGPoint(x: size.width - 24, y: y), anchor: .center)
                }

                // Max indicator line (orange dashed)
                if maxDB > 20 {
                    let y = yForDB(maxDB, height: size.height)
                    var maxLine = Path()
                    maxLine.move(to: CGPoint(x: 36, y: y))
                    maxLine.addLine(to: CGPoint(x: size.width - 48, y: y))
                    ctx.stroke(maxLine, with: .color(maxColor.opacity(0.85)), style: StrokeStyle(lineWidth: 1.0, dash: [4, 4]))

                    let maxBadge = Text(String(format: "MAX %.1f", maxDB))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(maxColor)
                    ctx.draw(maxBadge, at: CGPoint(x: size.width - 24, y: y), anchor: .center)
                }

                // Avg indicator line (white dotted)
                if avgDB > 20 {
                    let y = yForDB(avgDB, height: size.height)
                    var avgLine = Path()
                    avgLine.move(to: CGPoint(x: 36, y: y))
                    avgLine.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(avgLine, with: .color(Color.white.opacity(0.4)), style: StrokeStyle(lineWidth: 0.8, dash: [2, 3]))
                }

                // Plot Trend Curve
                guard samples.count > 1 else { return }
                let leftMargin: CGFloat = 36
                let usableWidth = size.width - leftMargin - 12
                let stepX = usableWidth / CGFloat(max(1, samples.count - 1))

                var trendPath = Path()
                for (i, dbfs) in samples.enumerated() {
                    let db = max(20.0, min(130.0, dbfs + 100.0))
                    let x = leftMargin + CGFloat(i) * stepX
                    let y = yForDB(db, height: size.height)
                    if i == 0 {
                        trendPath.move(to: CGPoint(x: x, y: y))
                    } else {
                        trendPath.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                ctx.stroke(trendPath, with: .color(trendColor), lineWidth: 1.8)
            }
        }
    }

    private func yForDB(_ db: Double, height: CGFloat) -> CGFloat {
        let minDB = 20.0
        let maxDB = 130.0
        let clamped = max(minDB, min(maxDB, db))
        let norm = (clamped - minDB) / (maxDB - minDB)
        return height - (CGFloat(norm) * (height - 30) + 16)
    }
}

// MARK: - Mode 5: Spectrogram Waterfall Canvas
private struct SpectrogramCanvas: View {
    let history: [SpectrogramSlice]
    let weightingUnit: String

    private let gridColor = Color(red: 0.16, green: 0.22, blue: 0.30)
    private let freqLabels = ["16K", "8K", "4K", "2K", "1K", "500", "100"]

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                // Left margin for frequency labels
                let leftMargin: CGFloat = 32
                let bottomMargin: CGFloat = 16
                let topMargin: CGFloat = 14
                let usableWidth = size.width - leftMargin - 4
                let usableHeight = size.height - topMargin - bottomMargin

                // Frequency labels on left axis
                for (i, f) in freqLabels.enumerated() {
                    let frac = CGFloat(i) / CGFloat(freqLabels.count - 1)
                    let y = topMargin + frac * usableHeight
                    let text = Text(f)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.45))
                    ctx.draw(text, at: CGPoint(x: 16, y: y), anchor: .center)

                    var hLine = Path()
                    hLine.move(to: CGPoint(x: leftMargin, y: y))
                    hLine.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(hLine, with: .color(gridColor.opacity(0.4)), lineWidth: 0.5)
                }

                // Time labels across bottom
                let times = ["-20s", "-15s", "-10s", "-5s", "Now"]
                for (i, t) in times.enumerated() {
                    let frac = CGFloat(i) / CGFloat(times.count - 1)
                    let x = leftMargin + frac * usableWidth
                    let text = Text(t)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.4))
                    ctx.draw(text, at: CGPoint(x: x, y: size.height - 8), anchor: .center)
                }

                // Render Heatmap Matrix
                guard !history.isEmpty else { return }
                let sliceWidth = max(2.0, usableWidth / CGFloat(history.count))

                for (sIdx, slice) in history.enumerated() {
                    let x = leftMargin + CGFloat(sIdx) * sliceWidth
                    let binCount = slice.magnitudes.count
                    guard binCount > 0 else { continue }
                    let binHeight = usableHeight / CGFloat(binCount)

                    for (bIdx, mag) in slice.magnitudes.enumerated() {
                        // High frequencies at top, low frequencies at bottom
                        let y = topMargin + CGFloat(binCount - 1 - bIdx) * binHeight
                        let cellRect = CGRect(x: x, y: y, width: sliceWidth + 0.5, height: binHeight + 0.5)
                        let color = colorForMagnitude(mag)
                        ctx.fill(Path(cellRect), with: .color(color))
                    }
                }
            }
        }
    }

    private func colorForMagnitude(_ mag: Float) -> Color {
        let m = max(0.0, min(1.0, Double(mag)))
        if m < 0.15 {
            return Color(red: 0.04, green: 0.08, blue: 0.18).opacity(0.9)
        } else if m < 0.35 {
            let t = (m - 0.15) / 0.20
            return Color(red: 0.04 + 0.05 * t, green: 0.15 + 0.55 * t, blue: 0.40 + 0.50 * t) // Cyan blue
        } else if m < 0.60 {
            let t = (m - 0.35) / 0.25
            return Color(red: 0.09 + 0.45 * t, green: 0.70 + 0.25 * t, blue: 0.90 - 0.65 * t) // Lime green
        } else if m < 0.85 {
            let t = (m - 0.60) / 0.25
            return Color(red: 0.54 + 0.44 * t, green: 0.95 - 0.10 * t, blue: 0.25 - 0.15 * t) // Golden yellow
        } else {
            let t = (m - 0.85) / 0.15
            return Color(red: 0.98, green: 0.85 - 0.55 * t, blue: 0.10 + 0.10 * t) // Orange red
        }
    }
}


// MARK: - Analog Gauge Dial
private struct AnalogGaugeDial: View {
    let level: Double
    let minLevel: Double
    let maxLevel: Double

    private let blueScale = Color(red: 0.22, green: 0.65, blue: 0.98)   // #38BDF8
    private let orangeScale = Color(red: 0.98, green: 0.44, blue: 0.16) // #FA7028

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let center = CGPoint(x: w / 2, y: h - 10)
            let radius = min(w / 2 - 16, h - 14)

            ZStack {
                // Background dial markings
                Canvas { ctx, size in
                    let minDB = 20.0
                    let maxDB = 130.0
                    let startAngle = -142.0
                    let endAngle = -38.0

                    // Split at 85 dB: 20-85 is blue, 85-130 is orange
                    let splitFrac = (85.0 - minDB) / (maxDB - minDB)
                    let splitDeg = startAngle + splitFrac * (endAngle - startAngle)

                    // Continuous curved arc lines along tick base
                    var blueArc = Path()
                    for deg in stride(from: startAngle, through: splitDeg, by: 1.0) {
                        let rad = deg * .pi / 180.0
                        let pt = CGPoint(x: center.x + CGFloat(cos(rad)) * (radius - 14), y: center.y + CGFloat(sin(rad)) * (radius - 14))
                        if deg == startAngle {
                            blueArc.move(to: pt)
                        } else {
                            blueArc.addLine(to: pt)
                        }
                    }
                    ctx.stroke(blueArc, with: .color(blueScale), lineWidth: 2.2)

                    var orangeArc = Path()
                    for deg in stride(from: splitDeg, through: endAngle, by: 1.0) {
                        let rad = deg * .pi / 180.0
                        let pt = CGPoint(x: center.x + CGFloat(cos(rad)) * (radius - 14), y: center.y + CGFloat(sin(rad)) * (radius - 14))
                        if deg == splitDeg {
                            orangeArc.move(to: pt)
                        } else {
                            orangeArc.addLine(to: pt)
                        }
                    }
                    ctx.stroke(orangeArc, with: .color(orangeScale), lineWidth: 2.2)

                    // Draw major and minor ticks
                    for db in stride(from: 20, through: 130, by: 1) {
                        let isMajor = db % 10 == 0
                        let isMedium = db % 5 == 0
                        let frac = (Double(db) - minDB) / (maxDB - minDB)
                        let deg = startAngle + frac * (endAngle - startAngle)
                        let rad = deg * .pi / 180.0

                        let tickColor = db <= 80 ? blueScale : orangeScale
                        let tickLen: CGFloat = isMajor ? 13 : (isMedium ? 8 : 4.5)
                        let strokeW: CGFloat = isMajor ? 2.0 : (isMedium ? 1.4 : 0.9)

                        let outerP = CGPoint(
                            x: center.x + CGFloat(cos(rad)) * radius,
                            y: center.y + CGFloat(sin(rad)) * radius
                        )
                        let innerP = CGPoint(
                            x: center.x + CGFloat(cos(rad)) * (radius - tickLen),
                            y: center.y + CGFloat(sin(rad)) * (radius - tickLen)
                        )

                        var p = Path()
                        p.move(to: innerP)
                        p.addLine(to: outerP)
                        ctx.stroke(p, with: .color(tickColor), lineWidth: strokeW)

                        // Draw major numbers
                        if isMajor {
                            let textRadius = radius - 23
                            let textP = CGPoint(
                                x: center.x + CGFloat(cos(rad)) * textRadius,
                                y: center.y + CGFloat(sin(rad)) * textRadius
                            )
                            let text = Text("\(db)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(tickColor)
                            ctx.draw(text, at: textP, anchor: .center)
                        }
                    }

                    // Radial indicator lines for MIN and MAX along the arc
                    if minLevel >= 20.0 {
                        let minDeg = startAngle + ((minLevel - minDB) / (maxDB - minDB)) * (endAngle - startAngle)
                        let rad = minDeg * .pi / 180.0
                        let p1 = CGPoint(x: center.x + CGFloat(cos(rad)) * (radius - 14), y: center.y + CGFloat(sin(rad)) * (radius - 14))
                        let p2 = CGPoint(x: center.x + CGFloat(cos(rad)) * (radius - 26), y: center.y + CGFloat(sin(rad)) * (radius - 26))
                        var minLine = Path()
                        minLine.move(to: p1)
                        minLine.addLine(to: p2)
                        ctx.stroke(minLine, with: .color(blueScale), lineWidth: 2.0)
                    }

                    if maxLevel >= 20.0 {
                        let maxDeg = startAngle + ((maxLevel - minDB) / (maxDB - minDB)) * (endAngle - startAngle)
                        let rad = maxDeg * .pi / 180.0
                        let p1 = CGPoint(x: center.x + CGFloat(cos(rad)) * (radius - 14), y: center.y + CGFloat(sin(rad)) * (radius - 14))
                        let p2 = CGPoint(x: center.x + CGFloat(cos(rad)) * (radius - 26), y: center.y + CGFloat(sin(rad)) * (radius - 26))
                        var maxLine = Path()
                        maxLine.move(to: p1)
                        maxLine.addLine(to: p2)
                        ctx.stroke(maxLine, with: .color(orangeScale), lineWidth: 2.0)
                    }
                }

                // Inner Dial MIN / MAX Readouts (positioned symmetrically to left & right)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MIN")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(blueScale)
                        Text(minLevel > 0 ? String(format: "%.1f", minLevel) : "--")
                            .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .padding(.leading, 32)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("MAX")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(orangeScale)
                        Text(maxLevel > 0 ? String(format: "%.1f", maxLevel) : "--")
                            .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .padding(.trailing, 32)
                }
                .offset(y: 20)

                // The Needle
                NeedleView(
                    center: center,
                    length: radius - 6,
                    angle: needleAngle(for: level)
                )
            }
        }
    }

    private func needleAngle(for db: Double) -> Double {
        let minDB = 20.0
        let maxDB = 130.0
        let startAngle = -142.0
        let endAngle = -38.0
        let clamped = max(minDB, min(maxDB, db > 0 ? db : minDB))
        let frac = (clamped - minDB) / (maxDB - minDB)
        return startAngle + frac * (endAngle - startAngle)
    }
}

// MARK: - Red Needle View
private struct NeedleView: View {
    let center: CGPoint
    let length: CGFloat
    let angle: Double

    var body: some View {
        Canvas { ctx, size in
            let rad = angle * .pi / 180.0
            let tip = CGPoint(
                x: center.x + CGFloat(cos(rad)) * length,
                y: center.y + CGFloat(sin(rad)) * length
            )
            let leftBase = CGPoint(
                x: center.x + CGFloat(cos(rad - .pi / 2)) * 3.5,
                y: center.y + CGFloat(sin(rad - .pi / 2)) * 3.5
            )
            let rightBase = CGPoint(
                x: center.x + CGFloat(cos(rad + .pi / 2)) * 3.5,
                y: center.y + CGFloat(sin(rad + .pi / 2)) * 3.5
            )

            var needle = Path()
            needle.move(to: leftBase)
            needle.addLine(to: tip)
            needle.addLine(to: rightBase)
            needle.closeSubpath()

            ctx.fill(needle, with: .color(Color(red: 0.94, green: 0.22, blue: 0.22)))

            // Center pivot cap
            let capRadius: CGFloat = 8
            let capRect = CGRect(x: center.x - capRadius, y: center.y - capRadius, width: capRadius * 2, height: capRadius * 2)
            ctx.fill(Circle().path(in: capRect), with: .color(Color(red: 0.12, green: 0.15, blue: 0.20)))
            ctx.stroke(Circle().path(in: capRect), with: .color(Color(white: 0.3)), lineWidth: 1.5)

            // Inner pivot dot
            let innerDot = CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)
            ctx.fill(Circle().path(in: innerDot), with: .color(Color.white.opacity(0.7)))
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: angle)
    }
}

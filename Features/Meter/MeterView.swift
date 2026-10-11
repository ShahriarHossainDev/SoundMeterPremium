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

    // Theme tokens matching screenshot
    private let darkBackground = Color(red: 0.04, green: 0.06, blue: 0.09) // #0A0F17
    private let cardBackground = Color(red: 0.07, green: 0.10, blue: 0.14) // #121A24
    private let accentBlue = Color(red: 0.22, green: 0.65, blue: 0.98)     // #38BDF8
    private let accentOrange = Color(red: 0.98, green: 0.44, blue: 0.16)   // #FA7028
    private let accentGreen = Color(red: 0.55, green: 0.88, blue: 0.25)    // #8CE040
    private let accentPink = Color(red: 0.94, green: 0.45, blue: 0.70)     // #F073B3

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                darkBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // 1. Top Audio Level Segmented LED Bar
                    topAudioMeterBar
                        .padding(.top, geometry.safeAreaInsets.top > 0 ? 0 : 8)
                        .padding(.bottom, 6)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 12) {
                            // 2. Frequency Spectrum Chart
                            spectrumSection
                                .frame(height: isFullScreenSpectrum ? 380 : 220)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                }
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
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
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < activeSegments ? accentGreen : Color(white: 0.15))
                    .frame(height: 7)
                    .shadow(color: index < activeSegments ? accentGreen.opacity(0.6) : .clear, radius: 2)
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: - 2. Frequency Spectrum Section
    private var spectrumSection: some View {
        ZStack(alignment: .top) {
            Color.black

            // Real-time FFT Curve Canvas
            SpectrumChartCanvas(
                curveData: model.spectrumCurveData,
                selectedFrequency: model.displayedFrequency,
                weightingUnit: model.unitSymbol
            )

            // Overlaid Spectrum HUD Controls
            VStack {
                HStack(alignment: .top) {
                    // Top-Left: Info button & Environment profile selector
                    HStack(spacing: 8) {
                        Button {
                            showingInfo = true
                        } label: {
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.14), in: Circle())
                        }

                        Button {
                            model.cycleEnvironmentProfile()
                        } label: {
                            VStack(spacing: 3) {
                                // Profile dots
                                HStack(spacing: 4) {
                                    ForEach(EnvironmentProfile.allCases) { profile in
                                        Circle()
                                            .fill(profile == model.environmentProfile ? Color.white : Color.white.opacity(0.25))
                                            .frame(width: 4, height: 4)
                                    }
                                }

                                Text(model.environmentProfile.rawValue)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.14), in: Capsule())
                        }
                    }

                    Spacer()

                    // Top-Right: Fullscreen button & Noise Alert Toggle
                    VStack(alignment: .trailing, spacing: 8) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isFullScreenSpectrum.toggle()
                            }
                        } label: {
                            Image(systemName: isFullScreenSpectrum ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.14), in: Circle())
                        }

                        Button {
                            noiseAlertEnabled.toggle()
                        } label: {
                            Image(systemName: noiseAlertEnabled ? "bell.fill" : "bell.slash.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(noiseAlertEnabled ? accentOrange : Color.white.opacity(0.85))
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.14), in: Circle())
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                Spacer()

                // Side frequency stepping navigation buttons
                HStack {
                    Button {
                        model.selectPreviousFrequency()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .bold))
                            Text(String(format: "%.0f Hz", model.displayedFrequency))
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.14), in: Capsule())
                    }

                    Spacer()

                    Button {
                        model.selectNextFrequency()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - 3. Action Toolbar (Matches Reference Icons & Orange Upgrade Button)
    private var actionToolbar: some View {
        HStack {
            // 1. Clipboard / Reports button
            Button {
                showingReports = true
            } label: {
                Image(systemName: "doc.plaintext")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(cardBackground, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            }

            // 2. Frequency Weighting mode button
            Button {
                cycleWeighting()
            } label: {
                Image(systemName: "tuningfork")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(model.weighting == .a ? accentOrange : .white)
                    .frame(width: 44, height: 44)
                    .background(cardBackground, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            }

            Spacer()

            // 3. Centered Orange Upgrade Button
            Button {
                showingProPaywall = true
            } label: {
                Text("Upgrade")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(cardBackground, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            }

            // 5. History / Trend button
            NavigationLink {
                HistoryView()
            } label: {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 16, weight: .semibold))
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
            ZStack(alignment: .bottom) {
                // Semicircular Analog Gauge Dial
                AnalogGaugeDial(
                    level: model.estimatedCurrentDB,
                    minLevel: model.estimatedMinimumDB,
                    maxLevel: model.estimatedMaximumDB
                )
                .frame(height: 195)

                // Bottom Overlay: Reset, Pause/Resume, Save & Elapsed Time
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
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 42, height: 42)
                            .background(Color.white.opacity(0.10), in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }

                    Spacer()

                    // Central Large Pause/Resume Button
                    Button {
                        model.togglePauseResume()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(Color(red: 0.98, green: 0.78, blue: 0.28), lineWidth: 2.5)
                                .frame(width: 66, height: 66)

                            Circle()
                                .fill(Color(red: 0.08, green: 0.11, blue: 0.16))
                                .frame(width: 61, height: 61)

                            Image(systemName: model.state == .measuring ? "pause.fill" : "play.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.28))
                        }
                    }

                    Spacer()

                    // Save / Export Button
                    Button {
                        showingSave = true
                    } label: {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 42, height: 42)
                            .background(Color.white.opacity(0.10), in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 30)
                .offset(y: 10)

                // Elapsed time label in bottom right corner
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(model.elapsedFormatted)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .padding(.trailing, 16)
                            .padding(.bottom, 6)
                    }
                }
            }
            .padding(.top, 12)
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
            VStack(spacing: 6) {
                Text("AVG")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08), in: Capsule())

                Text(model.estimatedAverageDB > 0 ? String(format: "%.1f", model.estimatedAverageDB) : "--")
                    .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accentBlue)
            }
            .frame(maxWidth: .infinity)

            // CENTER: Current Live Level
            VStack(spacing: 0) {
                Text(model.estimatedCurrentDB > 0 ? String(format: "%.1f", model.estimatedCurrentDB) : "--")
                    .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accentOrange)
            }
            .frame(maxWidth: .infinity)

            // RIGHT: MAX
            VStack(spacing: 6) {
                Text("MAX")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08), in: Capsule())

                Text(model.estimatedMaximumDB > 0 ? String(format: "%.1f", model.estimatedMaximumDB) : "--")
                    .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accentBlue)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
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
                    Label("Frequency Spectrum Analyzer", systemImage: "waveform.path")
                        .font(.title2.bold())
                        .foregroundStyle(accentOrange)

                    Text("This spectrum chart displays live Fast Fourier Transform (FFT) analysis computed directly from device microphone samples using Apple's Accelerate framework.")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Spectrum Curves").font(.headline)

                        HStack(alignment: .top, spacing: 12) {
                            Circle().fill(accentGreen).frame(width: 12, height: 12).padding(.top, 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Lime Green Curve — Instantaneous FFT")
                                    .font(.subheadline.bold())
                                Text("Real-time frequency distribution showing live harmonics and ambient acoustic energy.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }

                        HStack(alignment: .top, spacing: 12) {
                            Circle().fill(accentPink).frame(width: 12, height: 12).padding(.top, 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pink Curve — Peak Hold Envelope")
                                    .font(.subheadline.bold())
                                Text("Tracks the highest amplitude reached across each frequency band during this session.")
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
            .navigationTitle("Spectrum Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingInfo = false }
                }
            }
        }
    }
}

// MARK: - Frequency Spectrum Chart Canvas
private struct SpectrumChartCanvas: View {
    let curveData: SpectrumCurveData?
    let selectedFrequency: Double
    let weightingUnit: String

    private let gridColor = Color(red: 0.16, green: 0.22, blue: 0.30)
    private let pinkColor = Color(red: 0.94, green: 0.45, blue: 0.70)
    private let greenColor = Color(red: 0.55, green: 0.88, blue: 0.25)

    // Standard reference frequency labels
    private let frequencyLabels: [(name: String, freq: Double)] = [
        ("500", 500.0),
        ("1K", 1000.0),
        ("2K", 2000.0),
        ("4K", 4000.0),
        ("8K", 8000.0),
        ("16K", 16000.0)
    ]

    // Vertical dB scale markers (-20 to 120 dB)
    private let dbMarkers: [Int] = [120, 100, 80, 60, 40, 20, 0, -20]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Canvas { ctx, size in
                // 1. Draw Grid Lines & Scale Markers
                for db in dbMarkers {
                    let y = yForDB(Double(db), height: size.height)
                    var line = Path()
                    line.move(to: CGPoint(x: 32, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(line, with: .color(gridColor), lineWidth: 0.8)

                    // Y-Axis dB Labels
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

                    // Draw Selected/Peak Frequency Callout directly above the curve
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

// MARK: - Analog Gauge Dial
private struct AnalogGaugeDial: View {
    let level: Double
    let minLevel: Double
    let maxLevel: Double

    private let blueScale = Color(red: 0.22, green: 0.65, blue: 0.98)   // #38BDF8
    private let orangeScale = Color(red: 0.98, green: 0.44, blue: 0.16) // #FA7028
    private let needleRed = Color(red: 0.92, green: 0.22, blue: 0.22)   // #EA3838

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let center = CGPoint(x: w / 2, y: h + 15)
            let radius = min(w / 2 - 20, h + 5)

            ZStack {
                // Background dial markings
                Canvas { ctx, size in
                    // Sweep from 20 dB to 130 dB
                    let minDB = 20.0
                    let maxDB = 130.0
                    let startAngle = -142.0
                    let endAngle = -38.0

                    // Continuous curved arc line at the base of the ticks
                    let splitFrac = (85.0 - minDB) / (maxDB - minDB)
                    let splitDeg = startAngle + splitFrac * (endAngle - startAngle)

                    var blueArc = Path()
                    blueArc.addArc(
                        center: center,
                        radius: radius - 14,
                        startAngle: .degrees(startAngle),
                        endAngle: .degrees(splitDeg),
                        clockwise: false
                    )
                    ctx.stroke(blueArc, with: .color(blueScale), lineWidth: 2.2)

                    var orangeArc = Path()
                    orangeArc.addArc(
                        center: center,
                        radius: radius - 14,
                        startAngle: .degrees(splitDeg),
                        endAngle: .degrees(endAngle),
                        clockwise: false
                    )
                    ctx.stroke(orangeArc, with: .color(orangeScale), lineWidth: 2.2)

                    // Draw major and minor ticks
                    for db in stride(from: 20, through: 130, by: 1) {
                        let isMajor = db % 10 == 0
                        let isMedium = db % 5 == 0
                        let frac = (Double(db) - minDB) / (maxDB - minDB)
                        let deg = startAngle + frac * (endAngle - startAngle)
                        let rad = deg * .pi / 180.0

                        let tickColor = db <= 80 ? blueScale : orangeScale
                        let tickLen: CGFloat = isMajor ? 14 : (isMedium ? 9 : 5)
                        let strokeW: CGFloat = isMajor ? 2.2 : (isMedium ? 1.5 : 1.0)

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
                            let textRadius = radius - 24
                            let textP = CGPoint(
                                x: center.x + CGFloat(cos(rad)) * textRadius,
                                y: center.y + CGFloat(sin(rad)) * textRadius
                            )
                            let text = Text("\(db)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(tickColor)
                            ctx.draw(text, at: textP, anchor: .center)
                        }
                    }

                    // Radial indicator lines for MIN and MAX along the arc
                    if minLevel >= 20.0 {
                        let minDeg = startAngle + ((minLevel - minDB) / (maxDB - minDB)) * (endAngle - startAngle)
                        let rad = minDeg * .pi / 180.0
                        let p1 = CGPoint(x: center.x + CGFloat(cos(rad)) * (radius - 14), y: center.y + CGFloat(sin(rad)) * (radius - 14))
                        let p2 = CGPoint(x: center.x + CGFloat(cos(rad)) * (radius - 28), y: center.y + CGFloat(sin(rad)) * (radius - 28))
                        var minLine = Path()
                        minLine.move(to: p1)
                        minLine.addLine(to: p2)
                        ctx.stroke(minLine, with: .color(blueScale), lineWidth: 1.8)
                    }

                    if maxLevel >= 20.0 {
                        let maxDeg = startAngle + ((maxLevel - minDB) / (maxDB - minDB)) * (endAngle - startAngle)
                        let rad = maxDeg * .pi / 180.0
                        let p1 = CGPoint(x: center.x + CGFloat(cos(rad)) * (radius - 14), y: center.y + CGFloat(sin(rad)) * (radius - 14))
                        let p2 = CGPoint(x: center.x + CGFloat(cos(rad)) * (radius - 28), y: center.y + CGFloat(sin(rad)) * (radius - 28))
                        var maxLine = Path()
                        maxLine.move(to: p1)
                        maxLine.addLine(to: p2)
                        ctx.stroke(maxLine, with: .color(orangeScale), lineWidth: 1.8)
                    }
                }

                // Inner Dial MIN / MAX Indicators
                VStack(spacing: 2) {
                    HStack(spacing: 38) {
                        VStack(spacing: 2) {
                            Text("MIN")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(blueScale)
                            Text(minLevel > 0 ? String(format: "%.1f", minLevel) : "--")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.7))
                        }

                        VStack(spacing: 2) {
                            Text("MAX")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(orangeScale)
                            Text(maxLevel > 0 ? String(format: "%.1f", maxLevel) : "--")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                    }
                }
                .offset(y: 10)

                // The Needle
                NeedleView(
                    center: center,
                    length: radius - 8,
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
                x: center.x + CGFloat(cos(rad - .pi / 2)) * 4,
                y: center.y + CGFloat(sin(rad - .pi / 2)) * 4
            )
            let rightBase = CGPoint(
                x: center.x + CGFloat(cos(rad + .pi / 2)) * 4,
                y: center.y + CGFloat(sin(rad + .pi / 2)) * 4
            )

            var needle = Path()
            needle.move(to: leftBase)
            needle.addLine(to: tip)
            needle.addLine(to: rightBase)
            needle.closeSubpath()

            ctx.fill(needle, with: .color(Color(red: 0.94, green: 0.22, blue: 0.22)))

            // Center pivot cap
            let capRect = CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)
            ctx.fill(Circle().path(in: capRect), with: .color(Color(white: 0.15)))
            ctx.stroke(Circle().path(in: capRect), with: .color(.black), lineWidth: 2)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: angle)
    }
}

import SwiftUI

/// Occupational Noise Dosimeter Screen matching Decibel X / SoundMeter reference design.
struct DosimeterView: View {
    @StateObject private var model = DosimeterViewModel()
    @State private var showingUpgradePaywall = false
    @State private var showingInfoSheet = false

    // Dark theme colors matching reference screenshot
    private let navyBackground = Color(red: 0.05, green: 0.07, blue: 0.10)
    private let cardBackground = Color(red: 0.09, green: 0.11, blue: 0.15)
    private let controlBackground = Color(red: 0.13, green: 0.16, blue: 0.22)
    private let vibrantGreen = Color(red: 0.28, green: 0.90, blue: 0.38)
    private let vibrantOrange = Color(red: 1.0, green: 0.44, blue: 0.18)
    private let secondaryText = Color(red: 0.58, green: 0.63, blue: 0.72)

    var body: some View {
        ZStack {
            navyBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Header: Title + Restart/Reset Button
                headerBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // 1. Main Measurement Card (Info Button, Partial Ring Gauge, 4 Stats)
                        mainMeasurementCard

                        // 2. Settings Controls (Upgrade + Standard, Threshold + Exchange Rate)
                        settingsControlsGrid

                        // 3. Exposure Threshold List Card (85 dB, 88 dB, etc.)
                        exposureThresholdListCard

                        Spacer(minLength: 80) // Padding for floating bottom navigation bar
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
            }
        }
        .task {
            model.start()
        }
        .onAppear {
            model.reloadConfiguration()
        }
        .onDisappear {
            model.stop()
        }
        .sheet(isPresented: $showingUpgradePaywall) {
            NavigationStack {
                ProView()
            }
        }
        .sheet(isPresented: $showingInfoSheet) {
            NavigationStack {
                DosimeterInfoSheet()
            }
        }
        .alert("Dosimeter Error", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(alignment: .center) {
            Text("Dosimeter")
                .font(.system(size: 34, weight: .bold, design: .default))
                .foregroundStyle(.white)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    model.reset()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(controlBackground)
                        .frame(width: 44, height: 44)

                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .accessibilityLabel("Reset Dosimeter Session")
        }
    }

    // MARK: - Main Measurement Card
    private var mainMeasurementCard: some View {
        VStack(spacing: 18) {
            // Card Top Row: Info Button
            HStack {
                Button {
                    showingInfoSheet = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(controlBackground)
                            .frame(width: 38, height: 38)

                        Image(systemName: "book.pages")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .accessibilityLabel("Dosimeter Calculations Guide")

                Spacer()
            }

            // Circular Dose Gauge
            DoseArcGauge(
                percentage: model.dose,
                greenColor: vibrantGreen,
                trackColor: Color(red: 0.16, green: 0.19, blue: 0.26)
            )
            .frame(width: 230, height: 200)

            // 2x2 Statistics Grid with Green Divider Lines
            VStack(spacing: 14) {
                // Row 1: Duration & Instantaneous
                HStack(alignment: .top, spacing: 20) {
                    statisticCell(
                        title: "Duration",
                        subtitle: "hh:mm:ss",
                        value: model.durationString
                    )

                    statisticCell(
                        title: "Instantaneous",
                        subtitle: "dB",
                        value: model.instantaneousDB > 0 ? String(format: "%.1f", model.instantaneousDB) : "0.0"
                    )
                }

                // Row 2: TWA & Projected dose
                HStack(alignment: .top, spacing: 20) {
                    statisticCell(
                        title: "TWA",
                        subtitle: "dB",
                        value: String(format: "%.1f", model.twaDB)
                    )

                    statisticCell(
                        title: "Projected dose",
                        subtitle: "%",
                        value: String(format: "%.1f", model.projectedDose)
                    )
                }
            }
            .padding(.top, 4)
        }
        .padding(20)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // Single Stat Cell with Green Underline
    private func statisticCell(title: String, subtitle: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(secondaryText)
                }

                Spacer()

                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            // Thin Green Divider Line
            Rectangle()
                .fill(vibrantGreen)
                .frame(height: 1.5)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Settings Controls Grid
    private var settingsControlsGrid: some View {
        VStack(spacing: 10) {
            // Row 1: Upgrade button & Standard selector
            HStack(spacing: 10) {
                Button {
                    showingUpgradePaywall = true
                } label: {
                    Text("Upgrade")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(vibrantOrange, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                Menu {
                    ForEach(DosimeterStandard.allStandards) { standard in
                        Button {
                            model.selectedStandard = standard
                        } label: {
                            HStack {
                                Text(standard.name)
                                if model.selectedStandard == standard {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)

                        Text("Standard: \(model.selectedStandard.name)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(controlBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }

            // Row 2: Threshold control & Exchange-rate control
            HStack(spacing: 10) {
                Menu {
                    ForEach([70.0, 75.0, 80.0, 85.0, 90.0], id: \.self) { th in
                        Button("\(Int(th)) dB") {
                            model.threshold = th
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.to.line")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(secondaryText)

                        Text("Threshold: \(Int(model.threshold)) dB")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(controlBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                Menu {
                    ForEach([3.0, 4.0, 5.0], id: \.self) { rate in
                        Button("\(Int(rate)) dB") {
                            model.exchangeRate = rate
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(secondaryText)

                        Text("Exchange rate: \(Int(model.exchangeRate)) dB")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(controlBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }

    // MARK: - Exposure Threshold List Card
    private var exposureThresholdListCard: some View {
        VStack(spacing: 20) {
            ForEach(model.thresholdItems) { item in
                ExposureThresholdRowView(
                    item: item,
                    greenColor: vibrantGreen,
                    secondaryColor: secondaryText
                )
            }
        }
        .padding(20)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - Dose Partial Arc Gauge
private struct DoseArcGauge: View {
    let percentage: Double
    let greenColor: Color
    let trackColor: Color

    // Arc from 145 degrees (bottom left) to 395 degrees (bottom right) -> 250 degrees total sweep
    private let startAngle: Double = 145.0
    private let sweepAngle: Double = 250.0

    private var currentSweep: Double {
        let clamped = max(0.0, min(100.0, percentage))
        return (clamped / 100.0) * sweepAngle
    }

    var body: some View {
        GeometryReader { geo in
            let radius = min(geo.size.width, geo.size.height) / 2 - 16
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2 + 10)

            ZStack {
                // Background Track Arc
                ArcShape(startAngle: startAngle, sweepAngle: sweepAngle)
                    .stroke(trackColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)

                // Active Progress Arc
                if currentSweep > 0 {
                    ArcShape(startAngle: startAngle, sweepAngle: currentSweep)
                        .stroke(greenColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .frame(width: radius * 2, height: radius * 2)
                        .position(center)
                }

                // Green Indicator Dot at the head of the arc
                let indicatorAngle = (startAngle + currentSweep) * .pi / 180.0
                let dotX = center.x + radius * CGFloat(cos(indicatorAngle))
                let dotY = center.y + radius * CGFloat(sin(indicatorAngle))

                Circle()
                    .fill(greenColor)
                    .frame(width: 14, height: 14)
                    .position(x: dotX, y: dotY)

                // Central Readout: "0.0 % \n Dose"
                VStack(spacing: 4) {
                    HStack(alignment: .top, spacing: 2) {
                        Text(String(format: "%.1f", percentage))
                            .font(.system(size: 48, weight: .bold, design: .default))
                            .foregroundStyle(.white)

                        Text("%")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.top, 6)
                    }

                    Text("Dose")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(red: 0.58, green: 0.63, blue: 0.72))
                }
                .position(x: center.x, y: center.y - 4)
            }
        }
    }
}

// Custom Partial Arc Shape for Gauge
private struct ArcShape: Shape {
    let startAngle: Double
    let sweepAngle: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let start = Angle(degrees: startAngle)
        let end = Angle(degrees: startAngle + sweepAngle)

        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        return path
    }
}

// MARK: - Exposure Threshold Row View
private struct ExposureThresholdRowView: View {
    let item: ExposureThresholdItem
    let greenColor: Color
    let secondaryColor: Color

    private let totalSegments = 28

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            // Left: Large dB Level with Superscript
            HStack(alignment: .top, spacing: 2) {
                Text("\(Int(item.level))")
                    .font(.system(size: 32, weight: .bold, design: .default))
                    .foregroundStyle(.white)

                Text("dB")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 4)
            }
            .frame(width: 68, alignment: .leading)

            // Right: Pointer, Segmented Progress Bar, and Max Duration Labels
            VStack(alignment: .leading, spacing: 4) {
                // Percentage Pointer (Moves dynamically with exposure percentage)
                GeometryReader { geo in
                    let clampedFraction = max(0.0, min(1.0, item.percentage / 100.0))
                    let pointerX = clampedFraction * (geo.size.width - 24)

                    VStack(alignment: .center, spacing: 1) {
                        Text("\(Int(item.percentage))%")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 0.68, green: 0.76, blue: 0.88))

                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(Color(red: 0.52, green: 0.60, blue: 0.72))
                    }
                    .offset(x: pointerX)
                }
                .frame(height: 18)

                // Segmented Progress Bar
                SegmentedBarView(
                    progress: item.percentage / 100.0,
                    totalSegments: totalSegments,
                    activeColor: greenColor,
                    inactiveColor: Color(red: 0.16, green: 0.20, blue: 0.28)
                )
                .frame(height: 7)

                // Sub-labels: Elapsed Duration & Max Allowed Duration
                HStack {
                    Text(item.elapsedFormatted)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(secondaryColor)

                    Spacer()

                    Text(item.maxDurationFormatted)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(secondaryColor)
                }
                .padding(.top, 2)

                // Thin Horizontal Divider Line
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - Segmented Progress Bar View
private struct SegmentedBarView: View {
    let progress: Double
    let totalSegments: Int
    let activeColor: Color
    let inactiveColor: Color

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<totalSegments, id: \.self) { index in
                let thresholdFraction = Double(index) / Double(totalSegments)
                let isFilled = progress > thresholdFraction

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isFilled ? activeColor : inactiveColor)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Dosimeter Information & Disclaimers Modal
private struct DosimeterInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Occupational Noise Dosimeter", systemImage: "headphones")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text("A noise dosimeter measures personal sound exposure accumulated over a work shift or measurement period.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Cumulative Noise Dose (D)")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Noise Dose is the percentage of permissible daily noise exposure. 100% dose represents the maximum recommended exposure for an 8-hour shift.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("D = 100 × ∑ (Cn / Tn) %")
                            .font(.system(.body, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Time-Weighted Average (TWA)")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("TWA represents the constant sound level that would produce the equivalent accumulated dose over an 8-hour workday.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Standards Overview")
                            .font(.headline)
                            .foregroundStyle(.white)

                        StandardRow(name: "NIOSH", criterion: "85 dB", exchange: "3 dB", threshold: "80 dB", notes: "Recommended scientific exposure standard.")
                        StandardRow(name: "OSHA (HC)", criterion: "90 dB", exchange: "5 dB", threshold: "80 dB", notes: "Hearing conservation action level.")
                        StandardRow(name: "OSHA (PEL)", criterion: "90 dB", exchange: "5 dB", threshold: "90 dB", notes: "Permissible exposure limit compliance.")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Regulatory Disclaimer", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text("SoundMeter provides informative digital exposure estimates. Smartphone microphones are not certified Class 1 or Type 2 dosimeters and must not be used for statutory regulatory compliance.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(20)
            }
            .background(Color(red: 0.05, green: 0.07, blue: 0.10).ignoresSafeArea())
            .navigationTitle("Dosimeter Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}

private struct StandardRow: View {
    let name: String
    let criterion: String
    let exchange: String
    let threshold: String
    let notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.subheadline.bold()).foregroundStyle(.white)
                Spacer()
                Text("Crit: \(criterion) | Ex: \(exchange) | Thresh: \(threshold)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(notes).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

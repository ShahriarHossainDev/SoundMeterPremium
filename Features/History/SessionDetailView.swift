import SwiftUI
import SwiftData

struct SessionDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var session: MeasurementSession
    @State private var showingShare = false
    @State private var exportURL: URL?
    @State private var exportError: String?

    private var weightingModel: FrequencyWeighting? {
        FrequencyWeighting(rawValue: session.weighting)
    }

    private var unitSymbol: String {
        weightingModel?.unitSymbol ?? "dBFS"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PremiumCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.title).font(.title2.bold())
                        Text(session.startedAt, format: .dateTime.weekday(.wide).month().day().year().hour().minute())
                            .font(.subheadline).foregroundStyle(.secondary)
                        TextField("Add notes about this measurement", text: $session.notes, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(.top, 8)
                    }
                }

                HStack(spacing: 10) {
                    DetailStat(title: "Average", value: session.averageDBFS, unit: unitSymbol)
                    DetailStat(title: "Maximum", value: session.maximumDBFS, unit: unitSymbol)
                    DetailStat(title: "Minimum", value: session.minimumDBFS, unit: unitSymbol)
                }

                PremiumCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recorded trend").font(.headline)
                        SessionChart(values: session.samples.sorted { $0.elapsedSeconds < $1.elapsedSeconds }.map(\.levelDBFS))
                            .frame(height: 150)
                        Text("Saved display samples · \(unitSymbol)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                PremiumCard {
                    VStack(spacing: 12) {
                        LabeledContent("Duration", value: durationText(session.duration))
                        LabeledContent("Weighting", value: weightingModel?.displayName ?? session.weighting)
                        LabeledContent("Calibration offset", value: "\(session.calibrationOffsetDB, default: "%.1f") dB")
                        LabeledContent("Measurement unit", value: unitSymbol)
                    }
                }

                VStack(spacing: 10) {
                    Button {
                        do {
                            exportURL = try PDFExporter.export(session: session)
                            showingShare = true
                        } catch {
                            exportError = error.localizedDescription
                        }
                    } label: {
                        Label("Export PDF Report", systemImage: "doc.richtext.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .foregroundStyle(.black)

                    Button {
                        do {
                            exportURL = try CSVExporter.export(session: session)
                            showingShare = true
                        } catch {
                            exportError = error.localizedDescription
                        }
                    } label: {
                        Label("Export Raw CSV Data", systemImage: "tablecells")
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                    }
                    .buttonStyle(.bordered)
                }

                if let exportError {
                    Text(exportError).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { try? context.save() }
        .sheet(isPresented: $showingShare) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
    }

    private func durationText(_ duration: Double) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct DetailStat: View {
    let title: String
    let value: Double
    var unit: String = "dBFS"

    var body: some View {
        PremiumCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value, format: .number.precision(.fractionLength(1)))
                    .font(.system(.title3, design: .rounded).bold())
                Text(unit).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

private struct SessionChart: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            Path { path in
                guard values.count > 1 else { return }
                for i in values.indices {
                    let x = CGFloat(i) / CGFloat(values.count - 1) * geo.size.width
                    let y = geo.size.height * (1 - CGFloat(min(max((values[i] + 120) / 120, 0), 1)))
                    if i == values.startIndex { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }
}

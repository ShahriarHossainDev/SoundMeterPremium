import SwiftUI
import SwiftData

struct ReportsView: View {
    @Query(sort: \MeasurementSession.startedAt, order: .reverse)
    private var sessions: [MeasurementSession]
    @State private var shareURL: URL?
    @State private var showingShare = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Acoustic Reports & Data Export", systemImage: "doc.text.fill")
                            .font(.headline)
                            .foregroundStyle(AppTheme.accent)

                        Text("Generate executive PDF reports complete with embedded vector time-series charts, $L_{10}/L_{50}/L_{90}$ statistical percentiles, and compliance notices, or export raw CSV time-history datasets.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Recent Sessions (\(sessions.count))") {
                    if sessions.isEmpty {
                        ContentUnavailableView("No Sessions to Export", systemImage: "doc.text", description: Text("Record sound measurements from the Sound Meter tab to generate acoustic PDF reports."))
                    } else {
                        ForEach(sessions.prefix(15)) { session in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.title).font(.headline)
                                    let unit = FrequencyWeighting(rawValue: session.weighting)?.unitSymbol ?? "dBFS"
                                    HStack(spacing: 8) {
                                        Text(session.startedAt, format: .dateTime.month().day().hour().minute())
                                        Text("•")
                                        Text(formatDuration(session.duration))
                                        Text("•")
                                        Text(unit).bold().foregroundStyle(AppTheme.accent)
                                    }
                                    .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()

                                Menu {
                                    Button {
                                        exportPDF(session: session)
                                    } label: {
                                        Label("Export PDF Report", systemImage: "doc.richtext.fill")
                                    }

                                    Button {
                                        exportCSV(session: session)
                                    } label: {
                                        Label("Export CSV Data", systemImage: "tablecells")
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.body)
                                        Image(systemName: "chevron.down")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(AppTheme.accent)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(AppTheme.accent.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Export options for \(session.title)")
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Reports")
            .sheet(isPresented: $showingShare) {
                if let shareURL { ShareSheet(items: [shareURL]) }
            }
        }
    }

    private func exportPDF(session: MeasurementSession) {
        do {
            shareURL = try PDFExporter.export(session: session)
            showingShare = true
        } catch {
            errorMessage = "Failed to create PDF: \(error.localizedDescription)"
        }
    }

    private func exportCSV(session: MeasurementSession) {
        do {
            shareURL = try CSVExporter.export(session: session)
            showingShare = true
        } catch {
            errorMessage = "Failed to export CSV: \(error.localizedDescription)"
        }
    }

    private func formatDuration(_ duration: Double) -> String {
        let s = max(0, Int(duration))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

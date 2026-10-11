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
                    Label("Export saved sessions as CSV", systemImage: "tablecells")
                    Text("CSV reports contain session metadata and saved graph samples. Export a session from its detail screen.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Recent sessions") {
                    if sessions.isEmpty {
                        ContentUnavailableView("Nothing to Export", systemImage: "doc.text")
                    } else {
                        ForEach(sessions.prefix(10)) { session in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.title).font(.headline)
                                    Text(session.startedAt, format: .dateTime.month().day().hour().minute())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    do {
                                        shareURL = try CSVExporter.export(session: session)
                                        showingShare = true
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Export \(session.title)")
                            }
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Reports")
            .sheet(isPresented: $showingShare) {
                if let shareURL { ShareSheet(items: [shareURL]) }
            }
        }
    }
}

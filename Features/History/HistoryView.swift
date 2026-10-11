import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MeasurementSession.startedAt, order: .reverse)
    private var sessions: [MeasurementSession]
    @State private var searchText = ""

    private var filtered: [MeasurementSession] {
        guard !searchText.isEmpty else { return sessions }
        return sessions.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Measurements Yet" : "No Results",
                        systemImage: "waveform.path",
                        description: Text(searchText.isEmpty ? "Start a measurement and save it to see your history here." : "Try another search.")
                    )
                } else {
                    List {
                        ForEach(filtered) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                SessionRow(session: session)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Data")
            .searchable(text: $searchText, prompt: "Search sessions")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { ReportsView() } label: { Label("Reports", systemImage: "doc.text") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !filtered.isEmpty { EditButton() }
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(filtered[index]) }
        try? context.save()
    }
}

private struct SessionRow: View {
    let session: MeasurementSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path")
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 44, height: 44)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 5) {
                Text(session.title).font(.headline)
                Text(session.startedAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
                Text("Average \(session.averageDBFS, specifier: "%.1f") dBFS · \(durationText(session.duration))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func durationText(_ duration: Double) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

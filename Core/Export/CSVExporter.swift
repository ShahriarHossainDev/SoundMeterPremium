import Foundation

enum CSVExporter {
    static func export(session: MeasurementSession) throws -> URL {
        let safeName = session.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName)-\(session.id.uuidString.prefix(8)).csv")

        var rows = [
            "session_id,title,started_at,elapsed_seconds,level_dbfs,weighting",
            "\(session.id.uuidString),\(escape(session.title)),\(ISO8601DateFormatter().string(from: session.startedAt)),,,\(session.weighting)"
        ]

        for sample in session.samples.sorted(by: { $0.elapsedSeconds < $1.elapsedSeconds }) {
            rows.append("\(session.id.uuidString),\(escape(session.title)),,\(sample.elapsedSeconds),\(sample.levelDBFS),\(session.weighting)")
        }

        try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func escape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

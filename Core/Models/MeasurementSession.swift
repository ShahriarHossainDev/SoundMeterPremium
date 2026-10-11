import Foundation
import SwiftData

@Model
final class MeasurementSession {
    @Attribute(.unique) var id: UUID
    var title: String
    var startedAt: Date
    var endedAt: Date
    var duration: Double
    var averageDBFS: Double
    var maximumDBFS: Double
    var minimumDBFS: Double
    var weighting: String
    var calibrationOffsetDB: Double
    var notes: String

    @Relationship(deleteRule: .cascade, inverse: \MeasurementSample.session)
    var samples: [MeasurementSample] = []

    init(
        title: String = "Sound Session",
        startedAt: Date = .now,
        endedAt: Date = .now,
        duration: Double = 0,
        averageDBFS: Double = -120,
        maximumDBFS: Double = -120,
        minimumDBFS: Double = -120,
        weighting: String = "Z",
        calibrationOffsetDB: Double = 0,
        notes: String = ""
    ) {
        self.id = UUID()
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.averageDBFS = averageDBFS
        self.maximumDBFS = maximumDBFS
        self.minimumDBFS = minimumDBFS
        self.weighting = weighting
        self.calibrationOffsetDB = calibrationOffsetDB
        self.notes = notes
    }
}

@Model
final class MeasurementSample {
    @Attribute(.unique) var id: UUID
    var elapsedSeconds: Double
    var levelDBFS: Double
    var session: MeasurementSession?

    init(elapsedSeconds: Double, levelDBFS: Double, session: MeasurementSession? = nil) {
        self.id = UUID()
        self.elapsedSeconds = elapsedSeconds
        self.levelDBFS = levelDBFS
        self.session = session
    }
}

@Model
final class CalibrationProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var offsetDB: Double
    var updatedAt: Date

    init(name: String, offsetDB: Double = 0, updatedAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.offsetDB = offsetDB
        self.updatedAt = updatedAt
    }
}

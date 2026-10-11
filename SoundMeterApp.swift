import SwiftUI
import SwiftData

@main
struct SoundMeterApp: App {
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(colorScheme)
                .tint(AppTheme.accent)
        }
        .modelContainer(for: [MeasurementSession.self, MeasurementSample.self, CalibrationProfile.self])
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

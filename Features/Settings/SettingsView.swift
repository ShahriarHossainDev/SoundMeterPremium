import SwiftUI

// MARK: - Decibel X Style Settings Screen

struct SettingsView: View {
    // MARK: - AppStorage Persisted State
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("defaultWeighting") private var weighting = "A"
    @AppStorage("responseTime") private var responseTime = "Fast"
    @AppStorage("showSpectrumPeaks") private var showSpectrumPeaks = true
    @AppStorage("peakHoldEnabled") private var peakHoldEnabled = true
    @AppStorage("preventAppSleep") private var preventAppSleep = false
    @AppStorage("keepRunningInBackground") private var keepRunningInBackground = false
    @AppStorage("autoSaveEnabled") private var autoSaveEnabled = false
    @AppStorage("microphoneGainOffset") private var microphoneGainOffset = 0.0
    @AppStorage("dosimeterStandardID") private var dosimeterStandardID = "niosh"
    @AppStorage("dosimeterThreshold") private var dosimeterThreshold = 80.0
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    @AppStorage("healthKitEnabled") private var healthKitEnabled = false
    @AppStorage("noiseAlertEnabled") private var noiseAlertEnabled = false
    @AppStorage("noiseAlertThreshold") private var noiseAlertThreshold = -12.0
    @AppStorage("showUsageTooltips") private var showUsageTooltips = true

    // MARK: - View Presentation State
    @ObservedObject private var store = StoreKitManager.shared
    @State private var showingProPaywall = false
    @State private var showingBackgroundAudioSheet = false
    @State private var showingHealthKitSheet = false
    @State private var showingCloudKitSheet = false

    // MARK: - Visual Style Design Tokens
    private let darkBackground = Color(red: 0.04, green: 0.06, blue: 0.09) // #0A0F17
    private let cardBackground = Color(red: 0.07, green: 0.10, blue: 0.14) // #121A24
    private let separatorColor = Color.white.opacity(0.08)
    private let accentOrange = Color(red: 0.98, green: 0.44, blue: 0.16)   // #FA7028
    private let accentGreen = Color(red: 0.28, green: 0.84, blue: 0.37)    // #48D75E
    private let accentBlue = Color(red: 0.22, green: 0.65, blue: 0.98)     // #38BDF8
    private let secondaryText = Color(white: 0.58)

    var body: some View {
        NavigationStack {
            ZStack {
                darkBackground.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        // 1. Pro Upgrade Banner Card
                        proBannerCard

                        // 2. GENERAL Section
                        generalSection

                        // 3. CALIBRATION (TRIMMING) Section
                        calibrationSection

                        // 4. DOSIMETER Section
                        dosimeterSection

                        // 5. DATA Section
                        dataSection

                        // 6. LOUD NOISE DETECTION Section
                        loudNoiseSection

                        // 7. EXTENSIONS Section
                        extensionsSection

                        // 8. HELP Section
                        helpSection

                        // 9. APP VERSION & FOOTER
                        appVersionFooter

                        Spacer(minLength: 90) // Padding for floating bottom tab bar
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .sheet(isPresented: $showingProPaywall) {
                NavigationStack {
                    ProView()
                }
            }
            .sheet(isPresented: $showingBackgroundAudioSheet) {
                BackgroundAudioInfoSheet()
            }
            .sheet(isPresented: $showingHealthKitSheet) {
                HealthKitIntegrationSheet()
            }
            .sheet(isPresented: $showingCloudKitSheet) {
                CloudKitSyncInfoSheet()
            }
            .onAppear {
                applyPreventSleep(preventAppSleep)
            }
            .onChange(of: preventAppSleep) { _, newValue in
                applyPreventSleep(newValue)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 1. Pro Banner Card
    private var proBannerCard: some View {
        Button {
            showingProPaywall = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.98, green: 0.78, blue: 0.28).opacity(0.18))
                        .frame(width: 44, height: 44)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.28))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("SoundMeter Pro")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)

                        Text("PRO")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accentOrange, in: Capsule())
                    }

                    Text("Unlock A/C weighting, PDF reports & cloud sync")
                        .font(.system(size: 12))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(separatorColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. GENERAL Section
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("GENERAL")

            VStack(spacing: 0) {
                // Language
                NavigationLink {
                    LanguageSelectionView()
                } label: {
                    SettingsNavigationRow(
                        title: "Language",
                        value: "English"
                    )
                }

                rowDivider

                // Theme
                NavigationLink {
                    ThemeSelectionView(selectedTheme: $appearance)
                } label: {
                    SettingsNavigationRow(
                        title: "Theme",
                        value: appearanceTitle(appearance)
                    )
                }

                rowDivider

                // Frequency Weighting
                NavigationLink {
                    FrequencyWeightingSelectionView(selectedWeighting: $weighting)
                } label: {
                    SettingsNavigationRow(
                        title: "Frequency weighting",
                        value: weighting
                    )
                }

                rowDivider

                // Response Time
                NavigationLink {
                    ResponseTimeSelectionView(selectedResponseTime: $responseTime)
                } label: {
                    SettingsNavigationRow(
                        title: "Response time",
                        value: responseTimeDisplay(responseTime)
                    )
                }

                rowDivider

                // Show Spectrum Peaks
                SettingsToggleRow(
                    title: "Show spectrum peaks",
                    isOn: $showSpectrumPeaks
                )

                rowDivider

                // Peak Hold
                SettingsToggleRow(
                    title: "Peak hold",
                    isOn: $peakHoldEnabled
                )

                rowDivider

                // Prevent Application Sleep
                SettingsToggleRow(
                    title: "Prevent application sleep",
                    isOn: $preventAppSleep
                )

                rowDivider

                // Keep Running in Background
                SettingsActionRow(
                    title: "Keep running in background",
                    hasToggle: true,
                    toggleValue: keepRunningInBackground,
                    onToggle: {
                        keepRunningInBackground.toggle()
                        if keepRunningInBackground {
                            showingBackgroundAudioSheet = true
                        }
                    }
                )

                rowDivider

                // Auto Save
                SettingsActionRow(
                    title: "Auto save",
                    isLocked: !store.isProUser,
                    hasToggle: store.isProUser,
                    toggleValue: autoSaveEnabled,
                    onToggle: {
                        if store.isProUser {
                            autoSaveEnabled.toggle()
                        } else {
                            showingProPaywall = true
                        }
                    },
                    onTap: {
                        if !store.isProUser {
                            showingProPaywall = true
                        }
                    }
                )
            }
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(separatorColor, lineWidth: 1)
            )
        }
    }

    // MARK: - 3. CALIBRATION Section
    private var calibrationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("CALIBRATION (TRIMMING)")

            NavigationLink {
                CalibrationView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(width: 24)

                    Text("Calibration")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white)

                    Spacer()

                    Text(calibrationDisplay)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(secondaryText)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.3))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(separatorColor, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Text("Software gain offset trims the estimated acoustic level against an external reference meter. Does not certify laboratory acoustic SPL accuracy.")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.42))
                .padding(.horizontal, 6)
        }
    }

    // MARK: - 4. DOSIMETER Section
    private var dosimeterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("DOSIMETER")

            VStack(spacing: 0) {
                // Standard
                NavigationLink {
                    DosimeterStandardSelectionView(selectedStandardID: $dosimeterStandardID)
                } label: {
                    SettingsNavigationRow(
                        title: "Standard",
                        value: dosimeterStandardName(dosimeterStandardID)
                    )
                }

                rowDivider

                // Threshold
                NavigationLink {
                    DosimeterThresholdSelectionView(
                        threshold: $dosimeterThreshold,
                        standardName: dosimeterStandardName(dosimeterStandardID)
                    )
                } label: {
                    SettingsNavigationRow(
                        title: "Threshold",
                        value: String(format: "%.0f dB", dosimeterThreshold)
                    )
                }
            }
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(separatorColor, lineWidth: 1)
            )
        }
    }

    // MARK: - 5. DATA Section
    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("DATA")

            VStack(spacing: 0) {
                // iCloud sync
                HStack(spacing: 12) {
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(accentBlue)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud sync")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.white)

                        Text("Local SwiftData store")
                            .font(.system(size: 11))
                            .foregroundStyle(secondaryText)
                    }

                    Spacer()

                    Toggle("", isOn: $iCloudSyncEnabled)
                        .labelsHidden()
                        .tint(accentGreen)
                        .onChange(of: iCloudSyncEnabled) { _, newValue in
                            if newValue {
                                showingCloudKitSheet = true
                            }
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                rowDivider

                // Health app integration
                Button {
                    if store.isProUser {
                        showingHealthKitSheet = true
                    } else {
                        showingProPaywall = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(red: 1.0, green: 0.32, blue: 0.45))
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Health app integration")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundStyle(.white)

                                if !store.isProUser {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(accentOrange)
                                }
                            }

                            Text("Auto-export noise levels directly into Health app")
                                .font(.system(size: 11))
                                .foregroundStyle(secondaryText)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.3))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(separatorColor, lineWidth: 1)
            )
        }
    }

    // MARK: - 6. LOUD NOISE DETECTION Section
    private var loudNoiseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("LOUD NOISE DETECTION")

            VStack(spacing: 0) {
                // Enable toggle
                HStack(spacing: 12) {
                    Image(systemName: "waveform.badge.exclamationmark")
                        .font(.system(size: 16))
                        .foregroundStyle(noiseAlertEnabled ? accentOrange : Color.white.opacity(0.85))
                        .frame(width: 24)

                    Text("Enable")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white)

                    Spacer()

                    Toggle("", isOn: $noiseAlertEnabled)
                        .labelsHidden()
                        .tint(accentGreen)
                        .onChange(of: noiseAlertEnabled) { _, newValue in
                            if newValue {
                                Task {
                                    NoiseAlertManager.shared.requestPermissionIfNeeded()
                                }
                            }
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if noiseAlertEnabled {
                    rowDivider

                    // Threshold Slider Row
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Alert Threshold")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)

                            Spacer()

                            Text(String(format: "%.0f dBFS", noiseAlertThreshold))
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(accentOrange)
                        }

                        Slider(value: $noiseAlertThreshold, in: -60...(-1), step: 1)
                            .tint(accentOrange)

                        HStack {
                            Text("-60 dBFS (Sensitive)")
                                .font(.system(size: 10))
                                .foregroundStyle(secondaryText)
                            Spacer()
                            Text("-1 dBFS (Loudest)")
                                .font(.system(size: 10))
                                .foregroundStyle(secondaryText)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(separatorColor, lineWidth: 1)
            )

            Text("Alerts fire during active foreground measurement sessions with latching to prevent repeated notifications for sustained events.")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.42))
                .padding(.horizontal, 6)
        }
    }

    // MARK: - 7. EXTENSIONS Section
    private var extensionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("EXTENSIONS")

            NavigationLink {
                OiklaExtensionView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 16))
                        .foregroundStyle(accentOrange)
                        .frame(width: 24)

                    Text("OIKLA")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white)

                    Spacer()

                    Text("Pending")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(secondaryText)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.3))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(separatorColor, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 8. HELP Section
    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("HELP")

            VStack(spacing: 0) {
                // Show usage tooltips
                SettingsToggleRow(
                    title: "Show usage tooltips",
                    isOn: $showUsageTooltips
                )

                rowDivider

                // Glossary
                NavigationLink {
                    GlossaryView()
                } label: {
                    SettingsNavigationRow(
                        title: "Glossary",
                        value: ""
                    )
                }

                rowDivider

                // Privacy Policy
                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.raised.shield.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(accentBlue)
                            .frame(width: 24)

                        Text("Privacy Policy")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.white)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.3))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(separatorColor, lineWidth: 1)
            )
        }
    }

    // MARK: - 9. APP VERSION & FOOTER
    private var appVersionFooter: some View {
        VStack(spacing: 6) {
            Text("SoundMeter Premium v\(appVersionString) (\(appBuildString))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))

            Text("Local On-Device Audio Analysis • iOS 17+")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: - Helper Views & Functions
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(secondaryText)
            .padding(.horizontal, 6)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(separatorColor)
            .frame(height: 0.8)
            .padding(.leading, 16)
    }

    private var calibrationDisplay: String {
        if abs(microphoneGainOffset) < 0.01 {
            return "Linear"
        } else {
            return String(format: "Linear (%+.1f dB)", microphoneGainOffset)
        }
    }

    private func appearanceTitle(_ val: String) -> String {
        switch val {
        case "light": return "Light"
        case "dark": return "Dark"
        default: return "System"
        }
    }

    private func responseTimeDisplay(_ val: String) -> String {
        switch val {
        case "Slow": return "Slow (500 ms)"
        case "Impulse": return "Impulse (50 ms)"
        default: return "Fast (200 ms)"
        }
    }

    private func dosimeterStandardName(_ id: String) -> String {
        switch id {
        case "osha_hc": return "OSHA (HC)"
        case "osha_pel": return "OSHA (PEL)"
        case "acgih": return "ACGIH / EU"
        default: return "NIOSH"
        }
    }

    private var appVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var appBuildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private func applyPreventSleep(_ prevent: Bool) {
        UIApplication.shared.isIdleTimerDisabled = prevent
    }
}

// MARK: - Reusable Settings Navigation Row
private struct SettingsNavigationRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white)

            Spacer()

            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(white: 0.58))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Reusable Settings Toggle Row
private struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color(red: 0.28, green: 0.84, blue: 0.37))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Reusable Settings Action Row
private struct SettingsActionRow: View {
    let title: String
    var isLocked: Bool = false
    var hasToggle: Bool = false
    var toggleValue: Bool = false
    var onToggle: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil

    private let accentOrange = Color(red: 0.98, green: 0.44, blue: 0.16)
    private let accentGreen = Color(red: 0.28, green: 0.84, blue: 0.37)

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white)

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(accentOrange)
                }
            }

            Spacer()

            if hasToggle {
                Toggle("", isOn: Binding(
                    get: { toggleValue },
                    set: { _ in onToggle?() }
                ))
                .labelsHidden()
                .tint(accentGreen)
            } else if isLocked {
                Button {
                    onTap?()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.3))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            if isLocked {
                onTap?()
            }
        }
    }
}

// MARK: - Language Selection Screen
private struct LanguageSelectionView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.06, blue: 0.09).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("Select Application Language")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(white: 0.58))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                VStack(spacing: 0) {
                    HStack {
                        Text("English (US)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)

                        Spacer()

                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(red: 0.98, green: 0.44, blue: 0.16))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(Color(red: 0.07, green: 0.10, blue: 0.14), in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16)

                Text("SoundMeter Premium is currently localized in English (US). Additional international language catalogs will be loaded in forthcoming releases based on regional availability.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(.horizontal, 20)

                Spacer()
            }
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Theme Selection Screen
private struct ThemeSelectionView: View {
    @Binding var selectedTheme: String
    @Environment(\.dismiss) private var dismiss

    private let themes = [
        ("system", "System", "Matches your iOS device appearance settings."),
        ("dark", "Dark", "High contrast dark navy and charcoal palette."),
        ("light", "Light", "Clean daytime acoustic observation palette.")
    ]

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.06, blue: 0.09).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("Select Theme")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(white: 0.58))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                VStack(spacing: 0) {
                    ForEach(themes, id: \.0) { id, title, desc in
                        Button {
                            selectedTheme = id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(title)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(.white)
                                    Text(desc)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color(white: 0.55))
                                }

                                Spacer()

                                if selectedTheme == id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Color(red: 0.98, green: 0.44, blue: 0.16))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)

                        if id != themes.last?.0 {
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 0.8)
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(Color(red: 0.07, green: 0.10, blue: 0.14), in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16)

                Spacer()
            }
        }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Frequency Weighting Selection Screen
private struct FrequencyWeightingSelectionView: View {
    @Binding var selectedWeighting: String

    private let weightings = [
        (
            "A",
            "A-Weighting (dBA)",
            "Approximates the human ear's frequency response at moderate sound levels (40 phon curve). Attenuates low frequencies (< 1,000 Hz) and high frequencies (> 6,000 Hz). The primary standard for OSHA, NIOSH, and environmental noise assessments."
        ),
        (
            "C",
            "C-Weighting (dBC)",
            "Nearly flat response across the audible spectrum (31.5 Hz to 8,000 Hz) with minor roll-off at low and high extremes. Used to measure peak levels, explosive blast noises, and industrial mechanical low-frequency rumbling."
        ),
        (
            "Z",
            "Z-Weighting (dBZ)",
            "Zero frequency weighting (linear flat response from 10 Hz to 20,000 Hz ±1.5 dB). Accurately reflects raw acoustic energy for precision laboratory sound analysis, audio equipment testing, and octave band filtering."
        )
    ]

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.06, blue: 0.09).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Select IEC 61672-1 Weighting Filter")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(white: 0.58))
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    VStack(spacing: 0) {
                        ForEach(weightings, id: \.0) { code, title, desc in
                            Button {
                                selectedWeighting = code
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(title)
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(.white)

                                        Spacer()

                                        if selectedWeighting == code {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(Color(red: 0.98, green: 0.44, blue: 0.16))
                                        }
                                    }

                                    Text(desc)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.white.opacity(0.65))
                                        .lineSpacing(2)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)

                            if code != weightings.last?.0 {
                                Rectangle()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(height: 0.8)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color(red: 0.07, green: 0.10, blue: 0.14), in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 16)

                    Text("Connected directly to real-time biquad audio DSP filters in the measurement engine.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .padding(.horizontal, 20)
                }
            }
        }
        .navigationTitle("Frequency Weighting")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Response Time Selection Screen
private struct ResponseTimeSelectionView: View {
    @Binding var selectedResponseTime: String

    private let options = [
        ("Fast", "Fast (F — 200 ms)", "Standard dynamic response for general environmental noise and conversational monitoring. Follows rapid acoustic fluctuations closely."),
        ("Slow", "Slow (S — 500 ms)", "Damps rapid fluctuations to evaluate average noise in varying sound environments, industrial plant operations, and occupational assessments."),
        ("Impulse", "Impulse (I — 50 ms)", "High-speed 35–50 ms rise time specifically designed to capture sharp, transient acoustic events such as gunshots, hammer strikes, or fireworks.")
    ]

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.06, blue: 0.09).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("Select Time Weighting")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(white: 0.58))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                VStack(spacing: 0) {
                    ForEach(options, id: \.0) { id, title, desc in
                        Button {
                            selectedResponseTime = id
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(title)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(.white)

                                    Spacer()

                                    if selectedResponseTime == id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(Color(red: 0.98, green: 0.44, blue: 0.16))
                                    }
                                }

                                Text(desc)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.white.opacity(0.6))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)

                        if id != options.last?.0 {
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 0.8)
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(Color(red: 0.07, green: 0.10, blue: 0.14), in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16)

                Spacer()
            }
        }
        .navigationTitle("Response Time")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Dosimeter Standard Selection Screen
private struct DosimeterStandardSelectionView: View {
    @Binding var selectedStandardID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.06, blue: 0.09).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Select Occupational Standard")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(white: 0.58))
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    VStack(spacing: 0) {
                        ForEach(DosimeterStandard.allStandards) { standard in
                            Button {
                                selectedStandardID = standard.id
                                UserDefaults.standard.set(standard.id, forKey: "dosimeterStandardID")
                                UserDefaults.standard.set(standard.defaultThreshold, forKey: "dosimeterThreshold")
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(standard.name)
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(.white)

                                        Spacer()

                                        if selectedStandardID == standard.id {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(Color(red: 0.98, green: 0.44, blue: 0.16))
                                        }
                                    }

                                    HStack(spacing: 12) {
                                        Text("Criterion: \(Int(standard.criterionLevel)) dB")
                                        Text("Exchange: \(Int(standard.exchangeRate)) dB")
                                        Text("Threshold: \(Int(standard.defaultThreshold)) dB")
                                    }
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color(red: 0.22, green: 0.65, blue: 0.98))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)

                            if standard.id != DosimeterStandard.allStandards.last?.id {
                                Rectangle()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(height: 0.8)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color(red: 0.07, green: 0.10, blue: 0.14), in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 16)

                    Text("Selecting a standard updates the exchange rate (Q), criterion level (Lc), and default threshold (Lt) utilized by the Dosimeter calculation engine.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .padding(.horizontal, 20)
                }
            }
        }
        .navigationTitle("Dosimeter Standard")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Dosimeter Threshold Selection Screen
private struct DosimeterThresholdSelectionView: View {
    @Binding var threshold: Double
    let standardName: String
    private let availableThresholds = [70.0, 75.0, 80.0, 85.0, 90.0]

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.06, blue: 0.09).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("Select Threshold for \(standardName)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(white: 0.58))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                VStack(spacing: 0) {
                    ForEach(availableThresholds, id: \.self) { th in
                        Button {
                            threshold = th
                            UserDefaults.standard.set(th, forKey: "dosimeterThreshold")
                        } label: {
                            HStack {
                                Text("\(Int(th)) dB")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.white)

                                Spacer()

                                if abs(threshold - th) < 0.1 {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Color(red: 0.98, green: 0.44, blue: 0.16))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)

                        if th != availableThresholds.last {
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 0.8)
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(Color(red: 0.07, green: 0.10, blue: 0.14), in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16)

                Text("Sound levels below the selected threshold are excluded from dose integration calculations.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(.horizontal, 20)

                Spacer()
            }
        }
        .navigationTitle("Exposure Threshold")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - OIKLA Extension View
private struct OiklaExtensionView: View {
    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.06, blue: 0.09).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color(red: 0.98, green: 0.44, blue: 0.16).opacity(0.15))
                        .frame(width: 80, height: 80)

                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 36))
                        .foregroundStyle(Color(red: 0.98, green: 0.44, blue: 0.16))
                }

                VStack(spacing: 8) {
                    Text("OIKLA Extension Pending")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Hardware Module Integration")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(white: 0.58))
                }

                Text("No external OIKLA acoustic measurement accessory or transducer is currently paired with this device.\n\nWhen a certified OIKLA USB-C or Lightning hardware module is detected, digital calibration profiles and multi-channel telemetry will be activated automatically.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 32)

                Spacer()
            }
        }
        .navigationTitle("OIKLA")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Searchable Glossary View
private struct GlossaryView: View {
    @State private var searchText = ""

    struct GlossaryItem: Identifiable {
        let id = UUID()
        let term: String
        let definition: String
        let category: String
    }

    private let items: [GlossaryItem] = [
        GlossaryItem(
            term: "dBFS (Decibels relative to Full Scale)",
            definition: "Digital audio metering unit where 0 dBFS represents the maximum possible digital amplitude before waveform clipping. Mobile device microphones record sound digitally in dBFS.",
            category: "Digital Audio"
        ),
        GlossaryItem(
            term: "dB SPL (Sound Pressure Level)",
            definition: "Acoustic sound pressure referenced to the threshold of human hearing (20 micropascals / 0.00002 Pa). Requires physical acoustic calibration to convert digital levels into verified SPL.",
            category: "Acoustics"
        ),
        GlossaryItem(
            term: "RMS (Root Mean Square)",
            definition: "Statistical measure of the magnitude of a varying signal. In audio measurement, RMS represents the effective continuous energy level over a specified time window.",
            category: "Mathematics & DSP"
        ),
        GlossaryItem(
            term: "Frequency Weighting (A, C, Z)",
            definition: "Standardized frequency response curves (IEC 61672-1). A-weighting models human ear sensitivity, C-weighting measures high-energy industrial peaks, and Z-weighting is flat across 10 Hz–20 kHz.",
            category: "Standards"
        ),
        GlossaryItem(
            term: "Response Time (Fast, Slow, Impulse)",
            definition: "Exponential time constant for smoothing sound level variations. Fast uses 200 ms (IEC 125 ms constant), Slow uses 500 ms (IEC 1000 ms), and Impulse uses a rapid 50 ms rise time.",
            category: "Acoustics"
        ),
        GlossaryItem(
            term: "Peak Hold",
            definition: "Algorithm that captures and retains the highest sound level or FFT frequency spectral envelope reached over a continuous measurement period.",
            category: "Visualization"
        ),
        GlossaryItem(
            term: "Noise Dose (%)",
            definition: "The percentage of permissible daily occupational noise exposure accumulated over a work shift. 100% indicates the maximum permissible limit under NIOSH or OSHA guidelines.",
            category: "Dosimeter"
        ),
        GlossaryItem(
            term: "TWA (Time-Weighted Average)",
            definition: "The continuous constant sound level that would yield the same total noise dose over an 8-hour period as the fluctuating levels measured during the actual observation window.",
            category: "Dosimeter"
        ),
        GlossaryItem(
            term: "FFT (Fast Fourier Transform)",
            definition: "Efficient mathematical algorithm that computes the Discrete Fourier Transform of microphone audio, converting time-domain PCM samples into frequency-domain spectral magnitude bins.",
            category: "Mathematics & DSP"
        )
    ]

    private var filteredItems: [GlossaryItem] {
        if searchText.isEmpty {
            return items
        } else {
            return items.filter {
                $0.term.localizedCaseInsensitiveContains(searchText) ||
                $0.definition.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.06, blue: 0.09).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(filteredItems) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.term)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)

                                Spacer()

                                Text(item.category)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.22, green: 0.65, blue: 0.98))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(red: 0.22, green: 0.65, blue: 0.98).opacity(0.15), in: Capsule())
                            }

                            Text(item.definition)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.white.opacity(0.68))
                                .lineSpacing(2)
                        }
                        .padding(14)
                        .background(Color(red: 0.07, green: 0.10, blue: 0.14), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .searchable(text: $searchText, prompt: "Search acoustic terms...")
        .navigationTitle("Glossary")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Privacy Policy View
private struct PrivacyPolicyView: View {
    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.06, blue: 0.09).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Privacy & Data Protection", systemImage: "hand.raised.shield.fill")
                        .font(.title2.bold())
                        .foregroundStyle(Color(red: 0.22, green: 0.65, blue: 0.98))

                    Text("SoundMeter Premium is built on a privacy-first foundation. Your acoustic environment and audio recordings belong solely to you.")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.75))

                    Divider()
                        .background(Color.white.opacity(0.1))

                    VStack(alignment: .leading, spacing: 12) {
                        policyPoint(
                            title: "1. 100% On-Device Processing",
                            description: "All microphone samples, FFT spectrum transformations, and dosimeter computations are processed in real-time on your device using Apple's Accelerate and AVFoundation frameworks. Audio buffers are never streamed or uploaded to any remote server."
                        )

                        policyPoint(
                            title: "2. Zero Audio Recording Uploads",
                            description: "When using the live meter or camera overlay, microphone audio is used solely to compute decibel metrics and render user overlays. Raw microphone recordings are never stored without explicit user save action."
                        )

                        policyPoint(
                            title: "3. Local SwiftData Storage",
                            description: "Saved measurement sessions, calibration profiles, and historical notes are stored locally in your device's protected sandboxed database."
                        )

                        policyPoint(
                            title: "4. No Third-Party Analytics Trackers",
                            description: "This application contains zero third-party advertising SDKs or data brokers. All subscription purchases are transacted securely via Apple StoreKit 2."
                        )
                    }

                    Link("Apple Developer Privacy Documentation", destination: URL(string: "https://developer.apple.com/app-store/app-privacy-details/")!)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.98, green: 0.44, blue: 0.16))
                        .padding(.top, 8)
                }
                .padding(20)
            }
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func policyPoint(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.68))
                .lineSpacing(2)
        }
    }
}

// MARK: - Background Audio Info Sheet
private struct BackgroundAudioInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.06, blue: 0.09).ignoresSafeArea()

                VStack(spacing: 20) {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color(red: 0.98, green: 0.44, blue: 0.16))
                        .padding(.top, 24)

                    Text("Background Audio Execution")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Continuous background audio capture in iOS requires the 'Audio, AirPlay, and Picture in Picture' background mode entitlement configured in the Xcode project.\n\nIn this current configuration, acoustic analysis runs while the application is active in the foreground and temporarily pauses when backgrounded to conserve device battery and maintain system privacy.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 24)

                    Spacer()
                }
            }
            .navigationTitle("Background Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

// MARK: - HealthKit Integration Sheet
private struct HealthKitIntegrationSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.06, blue: 0.09).ignoresSafeArea()

                VStack(spacing: 20) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color(red: 1.0, green: 0.32, blue: 0.45))
                        .padding(.top, 24)

                    Text("Apple Health Integration")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Auto-exporting ambient noise exposure levels to Apple Health uses the 'Environmental Audio Exposure' category (HKQuantityTypeIdentifier.environmentalAudioExposure).\n\nEnabling synchronization requires HealthKit capabilities enabled on your Apple Developer Account and explicit user authorization inside the iOS Health privacy prompt.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 24)

                    Spacer()
                }
            }
            .navigationTitle("Health App Integration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

// MARK: - CloudKit Sync Info Sheet
private struct CloudKitSyncInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.06, blue: 0.09).ignoresSafeArea()

                VStack(spacing: 20) {
                    Image(systemName: "icloud.and.arrow.up.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color(red: 0.22, green: 0.65, blue: 0.98))
                        .padding(.top, 24)

                    Text("iCloud Sync Status")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)

                    Text("SoundMeter Premium uses an on-device SwiftData persistent store. Automatic cross-device synchronization requires an active iCloud account and CloudKit container entitlement (com.apple.developer.icloud-container-identifiers).\n\nYour local measurement records remain securely preserved on this device.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 24)

                    Spacer()
                }
            }
            .navigationTitle("iCloud Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var isReviewMode: Bool = false

    @State private var currentPage = 0
    @State private var micPermission: PermissionStatus = .notDetermined
    @State private var cameraPermission: PermissionStatus = .notDetermined
    @State private var wavePhase: CGFloat = 0.0

    enum PermissionStatus {
        case notDetermined
        case granted
        case denied

        var title: String {
            switch self {
            case .notDetermined: return "Not Requested"
            case .granted: return "Granted"
            case .denied: return "Access Denied"
            }
        }

        var iconName: String {
            switch self {
            case .notDetermined: return "questionmark.circle"
            case .granted: return "checkmark.circle.fill"
            case .denied: return "exclamationmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .notDetermined: return .secondary
            case .granted: return .green
            case .denied: return .red
            }
        }
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Navigation Bar
                HStack {
                    if isReviewMode {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        // SoundMeter Pro Badge
                        HStack(spacing: 6) {
                            Image(systemName: "waveform.path")
                                .font(.subheadline.bold())
                                .foregroundStyle(AppTheme.accent)
                            Text("SOUNDMETER PRO")
                                .font(.system(size: 11, weight: .heavy))
                                .tracking(1.2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                    }

                    Spacer()

                    if !isReviewMode && currentPage < 2 {
                        Button("Skip") {
                            withAnimation {
                                currentPage = 2
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 8)

                // Paging Carousel
                TabView(selection: $currentPage) {
                    onboardingSlideOne.tag(0)
                    onboardingSlideTwo.tag(1)
                    onboardingSlideThree.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                // Bottom Action Controls
                VStack(spacing: 12) {
                    if currentPage < 2 {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                currentPage += 1
                            }
                        } label: {
                            HStack {
                                Text("Continue")
                                Image(systemName: "arrow.right")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        Button {
                            completeOnboarding()
                        } label: {
                            HStack {
                                Text("Get Started")
                                Image(systemName: "checkmark")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .padding(.top, 8)
            }
        }
        .onAppear {
            refreshPermissions()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshPermissions()
            }
        }
    }

    // MARK: - Slide 1: Professional Sound Meter
    private var onboardingSlideOne: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 12)

                // Animated Sound Wave Artwork
                ZStack {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.12))
                        .frame(width: 170, height: 170)
                        .scaleEffect(1.0 + (wavePhase * 0.05))

                    Circle()
                        .stroke(AppTheme.accent.opacity(0.25), lineWidth: 2)
                        .frame(width: 140, height: 140)

                    AnimatedSoundWaveView()
                        .frame(width: 100, height: 60)
                }
                .frame(height: 180)

                VStack(spacing: 8) {
                    Text("Precision Sound Meter")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text("Real-time acoustic analysis powered by high-speed digital signal processing.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                // Feature Highlights
                VStack(spacing: 12) {
                    FeaturePill(
                        icon: "gauge.with.dots.needle.67percent",
                        title: "Fast, Slow & Impulse Response",
                        subtitle: "Standard exponential moving average time constants for transient and environmental sounds."
                    )
                    FeaturePill(
                        icon: "slider.horizontal.3",
                        title: "IEC 61672-1 Weighting (dBA, dBC, dBZ)",
                        subtitle: "Cascaded biquad filters normalized to human hearing curves and industrial noise standards."
                    )
                    FeaturePill(
                        icon: "chart.xyaxis.line",
                        title: "Time-History Trend Charts",
                        subtitle: "Track live peak, average (Leq), and minimum decibel statistics over time."
                    )
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 12)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Slide 2: Camera Telemetry & Spectrum
    private var onboardingSlideTwo: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 12)

                // Visual Telemetry Artwork
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(LinearGradient(
                            colors: [AppTheme.accent.opacity(0.18), AppTheme.secondaryAccent.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 170, height: 170)

                    VStack(spacing: 10) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 48, weight: .medium))
                            .foregroundStyle(AppTheme.accent)

                        HStack(spacing: 4) {
                            Text("74.5")
                                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                            Text("dBA")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.secondaryAccent)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.5), in: Capsule())
                    }
                }
                .frame(height: 180)

                VStack(spacing: 8) {
                    Text("Telemetry & Spectrum")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text("Capture photographic proof with burned-in acoustic telemetry and analyze spectral frequencies.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                // Feature Highlights
                VStack(spacing: 12) {
                    FeaturePill(
                        icon: "camera.fill",
                        title: "Photo & Video Decibel Burn-In",
                        subtitle: "Watermark photos and render frame-by-frame synchronized sound overlays into exported videos."
                    )
                    FeaturePill(
                        icon: "waveform.path",
                        title: "2048-Point FFT Analyzer",
                        subtitle: "Accelerate framework vDSP transforms displaying 48 spectral bands and peak frequency."
                    )
                    FeaturePill(
                        icon: "doc.richtext.fill",
                        title: "Executive PDF & CSV Reports",
                        subtitle: "Generate publication-grade PDF documents with L10/L50/L90 percentiles and export raw datasets."
                    )
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 12)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Slide 3: Permissions & Hearing Safety
    private var onboardingSlideThree: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 8)

                VStack(spacing: 8) {
                    Text("Permissions & Safety")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text("SoundMeter processes all acoustic data 100% on-device. Audio samples are never recorded or transmitted.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                // Permission Request Cards
                VStack(spacing: 14) {
                    // Microphone Card
                    PremiumCard {
                        HStack(spacing: 14) {
                            Image(systemName: "mic.fill")
                                .font(.title2)
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 44, height: 44)
                                .background(AppTheme.accent.opacity(0.12), in: Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Microphone Access")
                                    .font(.headline)
                                Text("Required for acoustic sound pressure measurement.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            if micPermission == .granted {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.green)
                            } else if micPermission == .denied {
                                Button("Settings") {
                                    openSettings()
                                }
                                .font(.caption.bold())
                                .buttonStyle(.bordered)
                                .tint(.red)
                            } else {
                                Button("Grant") {
                                    requestMicrophone()
                                }
                                .font(.caption.bold())
                                .buttonStyle(.borderedProminent)
                                .tint(AppTheme.accent)
                                .foregroundStyle(.black)
                            }
                        }
                    }

                    // Camera Card (Optional)
                    PremiumCard {
                        HStack(spacing: 14) {
                            Image(systemName: "camera.fill")
                                .font(.title2)
                                .foregroundStyle(AppTheme.secondaryAccent)
                                .frame(width: 44, height: 44)
                                .background(AppTheme.secondaryAccent.opacity(0.12), in: Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Camera Access")
                                    .font(.headline)
                                Text("Optional for live camera decibel overlay.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            if cameraPermission == .granted {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.green)
                            } else if cameraPermission == .denied {
                                Button("Settings") {
                                    openSettings()
                                }
                                .font(.caption.bold())
                                .buttonStyle(.bordered)
                                .tint(.red)
                            } else {
                                Button("Grant") {
                                    requestCamera()
                                }
                                .font(.caption.bold())
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                // Hearing Safety Reference Guide
                PremiumCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Hearing Safety Reference", systemImage: "ear.and.waveform")
                            .font(.headline)
                            .foregroundStyle(AppTheme.accent)

                        VStack(spacing: 8) {
                            SafetyThresholdRow(range: "< 70 dB", label: "Safe", description: "Normal conversation, quiet home.", color: .green)
                            Divider()
                            SafetyThresholdRow(range: "85 dB", label: "Caution", description: "OSHA/NIOSH limit for 8hr continuous exposure.", color: .orange)
                            Divider()
                            SafetyThresholdRow(range: "> 100 dB", label: "Hazardous", description: "Concerts, power tools. Ear protection required.", color: .red)
                        }
                    }
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 8)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Actions & Permissions Helpers

    private func refreshPermissions() {
        // Microphone Check
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                micPermission = .granted
            case .denied:
                micPermission = .denied
            case .undetermined:
                micPermission = .notDetermined
            @unknown default:
                micPermission = .notDetermined
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                micPermission = .granted
            case .denied:
                micPermission = .denied
            case .undetermined:
                micPermission = .notDetermined
            @unknown default:
                micPermission = .notDetermined
            }
        }

        // Camera Check
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermission = .granted
        case .denied, .restricted:
            cameraPermission = .denied
        case .notDetermined:
            cameraPermission = .notDetermined
        @unknown default:
            cameraPermission = .notDetermined
        }
    }

    private func requestMicrophone() {
        Task {
            if #available(iOS 17.0, *) {
                let granted = await AVAudioApplication.requestRecordPermission()
                await MainActor.run {
                    micPermission = granted ? .granted : .denied
                }
            } else {
                let session = AVAudioSession.sharedInstance()
                let granted = await withCheckedContinuation { continuation in
                    session.requestRecordPermission { continuation.resume(returning: $0) }
                }
                await MainActor.run {
                    micPermission = granted ? .granted : .denied
                }
            }
        }
    }

    private func requestCamera() {
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run {
                cameraPermission = granted ? .granted : .denied
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        if isReviewMode {
            dismiss()
        }
    }
}

// MARK: - Animated Sound Wave Vector Graphic

private struct AnimatedSoundWaveView: View {
    @State private var animating = false

    private let barCount = 7
    private let baseHeights: [CGFloat] = [18, 32, 48, 56, 42, 28, 14]

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(
                        colors: [AppTheme.accent, AppTheme.secondaryAccent],
                        startPoint: .bottom,
                        endPoint: .top
                    ))
                    .frame(width: 6, height: animating ? baseHeights[index] : max(8, baseHeights[index] * 0.45))
                    .animation(
                        Animation.easeInOut(duration: 0.65)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.1),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
}

// MARK: - Feature Pill Row

private struct FeaturePill: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        PremiumCard {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Safety Threshold Row

private struct SafetyThresholdRow: View {
    let range: String
    let label: String
    let description: String
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(range)
                .font(.caption.bold().monospacedDigit())
                .frame(width: 68, alignment: .leading)

            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color, in: Capsule())

            Spacer()

            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

import SwiftUI
import AVKit
import Photos

struct CameraView: View {

    var onClose: (() -> Void)? = nil

    @StateObject private var camera = CameraService()

    @State private var isVideoMode = false
    @State private var showPhotoPreview = false
    @State private var showVideoPreview = false
    @State private var showOverlaysSheet = false
    @State private var showFiltersCarousel = false
    @State private var showCloseWarningAlert = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private let cyan = Color(
        red: 0.0,
        green: 0.78,
        blue: 0.98
    )

    private let vibrantOrange = Color(
        red: 1.0,
        green: 0.44,
        blue: 0.18
    )

    var body: some View {

        GeometryReader { geometry in

            let availableHeight = geometry.size.height
            let availableWidth = geometry.size.width

            // Max viewport height reserved for the camera feed
            let maxViewportHeight = availableHeight * 0.62
            let desiredHeight = availableWidth * camera.aspectRatio.heightMultiplier
            let viewportHeight = min(maxViewportHeight, max(availableHeight * 0.45, desiredHeight))

            VStack(spacing: 0) {

                topControls
                    .frame(height: 105)
                    .background(Color.black)

                ZStack {

                    CameraPreview(session: camera.session)
                        .frame(
                            width: availableWidth,
                            height: viewportHeight
                        )
                        .clipped()

                    measurementOverlay
                        .frame(
                            width: availableWidth,
                            height: viewportHeight
                        )

                    if !camera.isConfigured && !camera.permissionDenied {
                        loadingOverlay
                    }

                    if camera.permissionDenied {
                        permissionOverlay
                    }

                    if camera.isInterrupted {
                        interruptionOverlay
                    }

                    if camera.isExportingVideo {
                        exportingOverlay
                    }
                }
                .frame(
                    width: availableWidth,
                    height: viewportHeight
                )
                .background(Color.black)
                .clipped()

                // Bottom Controls Area
                VStack(spacing: 14) {

                    if showFiltersCarousel {
                        filterSelectorCarousel
                    } else {
                        modeSelector
                    }

                    HStack(alignment: .center) {

                        sideButton(
                            title: "Overlays",
                            icon: "slider.horizontal.2.square"
                        ) {
                            showOverlaysSheet = true
                        }

                        Spacer()

                        captureButton

                        Spacer()

                        sideButton(
                            title: showFiltersCarousel ? "Done" : "Filters",
                            icon: showFiltersCarousel ? "checkmark.circle.fill" : "camera.filters"
                        ) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showFiltersCarousel.toggle()
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(Color.black)
            }
            .background(Color.black)
            .ignoresSafeArea(edges: .top)
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            camera.prepare()
        }
        .onAppear {
            camera.start()
        }
        .onDisappear {
            camera.stop()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                camera.start()
            case .background, .inactive:
                if camera.isRecording {
                    camera.stopRecording()
                }
                camera.stop()
            @unknown default:
                break
            }
        }
        .onChange(of: camera.capturedAnnotatedImage) { _, image in
            showPhotoPreview = image != nil
        }
        .onChange(of: camera.savedVideoURL) { _, url in
            showVideoPreview = url != nil
        }
        .alert(
            "Recording in Progress",
            isPresented: $showCloseWarningAlert
        ) {
            Button("Stop & Exit", role: .destructive) {
                camera.stopRecording()
                closeCamera()
            }
            Button("Continue Recording", role: .cancel) {}
        } message: {
            Text("A video is currently being recorded. Do you want to stop and close the camera?")
        }
        .alert(
            "Camera",
            isPresented: Binding(
                get: { camera.errorMessage != nil },
                set: { value in
                    if !value {
                        camera.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                camera.errorMessage = nil
            }
        } message: {
            Text(camera.errorMessage ?? "")
        }
        .sheet(isPresented: $showPhotoPreview) {
            if let annotated = camera.capturedAnnotatedImage,
               let raw = camera.capturedRawImage {
                MediaPhotoReview(
                    annotatedImage: annotated,
                    rawImage: raw,
                    onSave: { imageToSave in
                        camera.savePhoto(imageToSave) { _ in }
                    }
                )
            }
        }
        .sheet(isPresented: $showVideoPreview) {
            if let url = camera.savedVideoURL {
                MediaVideoReview(
                    url: url,
                    onSave: {
                        camera.saveVideo(url: url) { _ in }
                    }
                )
            }
        }
        .sheet(isPresented: $showOverlaysSheet) {
            CameraOverlaySettingsSheet(
                settings: $camera.overlaySettings,
                locationService: camera.locationService
            )
        }
    }

    // MARK: - Close Camera Action

    private func handleCloseTap() {
        if camera.isRecording {
            showCloseWarningAlert = true
        } else {
            closeCamera()
        }
    }

    private func closeCamera() {
        camera.stop()
        if let onClose {
            onClose()
        }
        NotificationCenter.default.post(name: .switchToMeterTab, object: nil)
        dismiss()
    }

    // MARK: - Top Controls

    private var topControls: some View {

        VStack {

            HStack(alignment: .center, spacing: 14) {

                Button {
                    handleCloseTap()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Close camera")

                Spacer()

                // Aspect Ratio Selector Menu
                Menu {
                    ForEach(CameraAspectRatio.allCases) { ratio in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                camera.aspectRatio = ratio
                            }
                        } label: {
                            HStack {
                                Text(ratio.rawValue)
                                if camera.aspectRatio == ratio {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "aspectratio")
                            .font(.system(size: 14, weight: .semibold))
                        Text(camera.aspectRatio.rawValue)
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                }
                .disabled(camera.isRecording)

                // Flash Selector Menu
                Menu {
                    Button {
                        camera.setFlashMode(.auto)
                    } label: {
                        Label("Auto Flash", systemImage: "bolt.badge.automatic")
                    }
                    Button {
                        camera.setFlashMode(.on)
                    } label: {
                        Label("Flash On", systemImage: "bolt.fill")
                    }
                    Button {
                        camera.setFlashMode(.off)
                    } label: {
                        Label("Flash Off", systemImage: "bolt.slash.fill")
                    }
                } label: {
                    Image(systemName: camera.flashMode.iconName)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(camera.isFlashAvailable ? (camera.flashMode == .off ? .white.opacity(0.7) : .yellow) : .gray)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .disabled(!camera.isFlashAvailable || camera.isRecording)

                // Camera Switch Button
                Button {
                    camera.switchCamera()
                } label: {
                    Image(systemName: "camera.rotate")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(camera.isRecording ? .gray : .white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .disabled(camera.isRecording)
                .accessibilityLabel("Switch front and back camera")
            }
            .padding(.horizontal, 20)
            .padding(.top, 50)

            Spacer()
        }
    }

    // MARK: - Measurement Overlay (HUD)

    private var measurementOverlay: some View {

        VStack(spacing: 0) {

            // Top Row: Sound Reading (Left) & Compact Stats (Right)
            HStack(alignment: .top) {

                if camera.overlaySettings.showSoundLevel {
                    VStack(alignment: .leading, spacing: 2) {

                        HStack(alignment: .firstTextBaseline, spacing: 4) {

                            let displayVal = camera.overlaySettings.useAcousticScale
                                ? camera.currentAcousticDB
                                : camera.currentDBFS

                            Text(displayVal, format: .number.precision(.fractionLength(1)))
                                .font(.system(size: 58, weight: .ultraLight, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)

                            let unitText = camera.overlaySettings.useAcousticScale
                                ? (UserDefaults.standard.string(forKey: "defaultWeighting").map { "dB\($0)" } ?? "dBA")
                                : "dBFS"

                            Text(unitText)
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                        }

                        Text("LIVE SOUND LEVEL")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                } else {
                    Spacer().frame(width: 1)
                }

                Spacer()

                // Center Recording Banner if active
                if camera.isRecording {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)

                        Text("REC \(camera.recordingDurationFormatted)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.red.opacity(0.8), lineWidth: 1)
                    )

                    Spacer()
                }

                // Compact Statistics Stack in Top-Right
                if camera.overlaySettings.showStatistics {
                    VStack(alignment: .trailing, spacing: 4) {

                        if camera.overlaySettings.showAverage {
                            let v = camera.overlaySettings.useAcousticScale ? camera.averageAcousticDB : camera.averageDBFS
                            statisticRow("AVG", v)
                        }

                        if camera.overlaySettings.showMinimum {
                            let v = camera.overlaySettings.useAcousticScale ? camera.minimumAcousticDB : camera.minimumDBFS
                            statisticRow("MIN", v)
                        }

                        if camera.overlaySettings.showMaximum {
                            let v = camera.overlaySettings.useAcousticScale ? camera.maximumAcousticDB : camera.maximumDBFS
                            statisticRow("MAX", v)
                        }

                        if camera.overlaySettings.showPeak {
                            let v = camera.overlaySettings.useAcousticScale ? camera.peakAcousticDB : camera.peakDBFS
                            statisticRow("PEAK", v)
                        }
                    }
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            // Active Filter Badge
            if camera.selectedFilter != .original {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: camera.selectedFilter.iconName)
                            .font(.system(size: 10, weight: .bold))
                        Text(camera.selectedFilter.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(cyan)
                    .clipShape(Capsule())
                    .shadow(color: cyan.opacity(0.4), radius: 4)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }

            Spacer()

            // Bottom Row: Watermark (Left) & Location/Timestamp (Right)
            HStack(alignment: .bottom) {

                if camera.overlaySettings.showWatermark {
                    Text("#SoundMeter")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {

                    if camera.overlaySettings.showDuration && !camera.isRecording {
                        HStack(spacing: 4) {
                            Image(systemName: "stopwatch")
                                .font(.system(size: 10))
                            Text(camera.recordingDurationFormatted)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(.white.opacity(0.85))
                    }

                    if camera.overlaySettings.showLocation, let loc = camera.locationService.locationName, !loc.isEmpty {
                        Text("📍 \(loc)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(cyan)
                    }

                    if camera.overlaySettings.showTimestamp {
                        Text(Date.now, format: .dateTime.hour().minute())
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)

                        Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day().year())
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.4),
                    Color.clear,
                    Color.black.opacity(0.5)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }

    private func statisticRow(_ title: String, _ value: Double) -> some View {
        HStack(spacing: 4) {
            Text("\(title):")
                .foregroundStyle(.white.opacity(0.75))
            Text(value, format: .number.precision(.fractionLength(1)))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Filter Selector Carousel

    private var filterSelectorCarousel: some View {
        VStack(spacing: 8) {
            HStack {
                Label("PHOTO & VIDEO FILTERS", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(cyan)
                    .tracking(1.4)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showFiltersCarousel = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(CameraFilter.allCases) { filter in
                        let isSelected = camera.selectedFilter == filter

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                camera.selectedFilter = filter
                            }
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                        } label: {
                            VStack(spacing: 5) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: filter.previewGradient,
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 46, height: 46)

                                    Image(systemName: filter.iconName)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(.white)

                                    if isSelected {
                                        Circle()
                                            .stroke(cyan, lineWidth: 3)
                                            .frame(width: 54, height: 54)
                                            .shadow(color: cyan.opacity(0.6), radius: 5)
                                    }
                                }
                                .frame(width: 56, height: 56)

                                Text(filter.rawValue)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? cyan : .white)

                                Text(filter.subtitle)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .scaleEffect(isSelected ? 1.05 : 1.0)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Mode Selector

    private var modeSelector: some View {
        HStack(spacing: 56) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isVideoMode = false
                }
            } label: {
                VStack(spacing: 4) {
                    Text("PHOTO")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(!isVideoMode ? Color.yellow : Color.gray)

                    Circle()
                        .fill(!isVideoMode ? Color.yellow : Color.clear)
                        .frame(width: 4, height: 4)
                }
            }
            .disabled(camera.isRecording || camera.isExportingVideo)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isVideoMode = true
                }
            } label: {
                VStack(spacing: 4) {
                    Text("VIDEO")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isVideoMode ? Color.yellow : Color.gray)

                    Circle()
                        .fill(isVideoMode ? Color.yellow : Color.clear)
                        .frame(width: 4, height: 4)
                }
            }
            .disabled(camera.isRecording || camera.isExportingVideo)
        }
    }

    // MARK: - Capture Button

    private var captureButton: some View {
        Button {
            if isVideoMode {
                if camera.isRecording {
                    camera.stopRecording()
                } else {
                    camera.startRecording()
                }
            } else {
                camera.capturePhoto()
            }
        } label: {
            ZStack {
                if !isVideoMode {
                    // PHOTO Shutter: Cyan outline around white circular shutter
                    Circle()
                        .stroke(cyan, lineWidth: 3.5)
                        .frame(width: 78, height: 78)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 64, height: 64)
                } else {
                    // VIDEO Shutter: Red indicator transitioning to stop square
                    Circle()
                        .stroke(camera.isRecording ? Color.red : Color.white.opacity(0.85), lineWidth: 3.5)
                        .frame(width: 78, height: 78)

                    if camera.isRecording {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red)
                            .frame(width: 28, height: 28)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 64, height: 64)
                    }
                }
            }
        }
        .disabled(camera.isExportingVideo)
    }

    // MARK: - Side Button

    private func sideButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.gray)
            }
            .frame(width: 68)
        }
        .disabled(camera.isRecording || camera.isExportingVideo)
    }

    // MARK: - Overlays for Loading, Permission & Export

    private var loadingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(cyan)
                .scaleEffect(1.2)

            Text("Initializing Camera...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.85))
    }

    private var interruptionOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.yellow)

            Text("Camera Interrupted")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            Text("The camera feed was paused by another app or system event.")
                .font(.system(size: 12))
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.85))
    }

    private var permissionOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 44))
                .foregroundStyle(.yellow)

            Text("Camera & Microphone Access Required")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)

            Text("SoundMeter needs access to measure sound levels and capture photo/video overlays.")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(cyan)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
    }

    private var exportingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView(value: camera.exportProgress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(cyan)
                .padding(.horizontal, 40)

            Text("Processing Sound Overlay...")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            Text("\(Int(camera.exportProgress * 100))%")
                .font(.system(size: 13))
                .foregroundStyle(.gray)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.85))
    }
}

// MARK: - Overlay Settings Sheet

private struct CameraOverlaySettingsSheet: View {

    @Binding var settings: OverlaySettings
    @ObservedObject var locationService: CameraLocationManager

    @Environment(\.dismiss) private var dismiss

    private let cyan = Color(red: 0.0, green: 0.78, blue: 0.98)
    private let cardBackground = Color(red: 0.08, green: 0.11, blue: 0.16)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Customize elements rendered on the live preview, captured photos, and exported videos.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                Section("SOUND METRICS") {
                    Toggle(isOn: $settings.showSoundLevel) {
                        Label("Live Sound Level", systemImage: "waveform")
                    }
                    .tint(cyan)

                    Toggle(isOn: $settings.useAcousticScale) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Calibrated Acoustic dB", systemImage: "gauge")
                            Text("When enabled, displays dBA/dBC calibrated acoustic level. When disabled, displays digital dBFS.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(cyan)

                    Toggle(isOn: $settings.showAverage) {
                        Label("Average (AVG)", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .tint(cyan)

                    Toggle(isOn: $settings.showMinimum) {
                        Label("Minimum (MIN)", systemImage: "arrow.down.to.line")
                    }
                    .tint(cyan)

                    Toggle(isOn: $settings.showMaximum) {
                        Label("Maximum (MAX)", systemImage: "arrow.up.to.line")
                    }
                    .tint(cyan)

                    Toggle(isOn: $settings.showPeak) {
                        Label("Peak (PEAK)", systemImage: "waveform.path.badge.plus")
                    }
                    .tint(cyan)
                }
                .listRowBackground(cardBackground)

                Section("METADATA & BRANDING") {
                    Toggle(isOn: $settings.showDuration) {
                        Label("Measurement Duration", systemImage: "stopwatch")
                    }
                    .tint(cyan)

                    Toggle(isOn: $settings.showTimestamp) {
                        Label("Date & Time Stamp", systemImage: "calendar")
                    }
                    .tint(cyan)

                    Toggle(isOn: $settings.showLocation) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Location Stamp", systemImage: "location.fill")
                            if settings.showLocation {
                                if let loc = locationService.locationName {
                                    Text("Current: \(loc)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(cyan)
                                } else {
                                    Text("Resolving current city...")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .tint(cyan)
                    .onChange(of: settings.showLocation) { _, newValue in
                        if newValue {
                            locationService.requestPermissionIfNeeded()
                        }
                    }

                    Toggle(isOn: $settings.showWatermark) {
                        Label("Watermark (#SoundMeter)", systemImage: "tag.fill")
                    }
                    .tint(cyan)
                }
                .listRowBackground(cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.04, green: 0.06, blue: 0.09))
            .navigationTitle("Overlay Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        settings.save()
                        dismiss()
                    }
                    .foregroundStyle(cyan)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Photo Review

private struct MediaPhotoReview: View {

    let annotatedImage: UIImage
    let rawImage: UIImage
    let onSave: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var showAnnotated = true
    @State private var isSaved = false
    @State private var isSaving = false

    private let cyan = Color(red: 0.0, green: 0.78, blue: 0.98)

    private var activeImage: UIImage {
        showAnnotated ? annotatedImage : rawImage
    }

    var body: some View {

        NavigationStack {

            ZStack {

                Color.black.ignoresSafeArea()

                VStack(spacing: 12) {

                    Image(uiImage: activeImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 12)

                    Picker("Annotation", selection: $showAnnotated) {
                        Text("Annotated Overlay").tag(true)
                        Text("Clean Photo").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("Photo Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button("Retake") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }

                ToolbarItemGroup(placement: .confirmationAction) {

                    ShareLink(
                        item: Image(uiImage: activeImage),
                        preview: SharePreview("SoundMeter Photo", image: Image(uiImage: activeImage))
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(cyan)
                    }

                    Button {
                        isSaving = true
                        onSave(activeImage)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isSaving = false
                            isSaved = true
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(cyan)
                        } else {
                            Label(
                                isSaved ? "Saved" : "Save",
                                systemImage: isSaved ? "checkmark.circle.fill" : "square.and.arrow.down"
                            )
                            .foregroundStyle(isSaved ? .green : cyan)
                        }
                    }
                    .disabled(isSaved || isSaving)
                }
            }
        }
    }
}

// MARK: - Video Review

private struct MediaVideoReview: View {

    let url: URL
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var isSaved = false
    @State private var isSaving = false

    private let cyan = Color(red: 0.0, green: 0.78, blue: 0.98)

    var body: some View {

        NavigationStack {

            ZStack {

                Color.black.ignoresSafeArea()

                VideoPlayer(player: AVPlayer(url: url))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 12)
            }
            .navigationTitle("Video Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button("Retake") {
                        try? FileManager.default.removeItem(at: url)
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }

                ToolbarItemGroup(placement: .confirmationAction) {

                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(cyan)
                    }

                    Button {
                        isSaving = true
                        onSave()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isSaving = false
                            isSaved = true
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(cyan)
                        } else {
                            Label(
                                isSaved ? "Saved" : "Save",
                                systemImage: isSaved ? "checkmark.circle.fill" : "square.and.arrow.down"
                            )
                            .foregroundStyle(isSaved ? .green : cyan)
                        }
                    }
                    .disabled(isSaved || isSaving)
                }
            }
        }
    }
}

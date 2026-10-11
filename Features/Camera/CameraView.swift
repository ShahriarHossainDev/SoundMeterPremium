import SwiftUI
import AVKit

struct CameraView: View {

    @StateObject private var camera = CameraService()

    @State private var isVideoMode = false
    @State private var showPhotoPreview = false
    @State private var showVideoPreview = false
    @State private var showOverlays = false
    @State private var showFilters = false

    @Environment(\.dismiss) private var dismiss

    private let cyan = Color(
        red: 0.0,
        green: 0.78,
        blue: 0.98
    )

    var body: some View {

        GeometryReader { geometry in

            VStack(spacing: 0) {

                topControls
                    .frame(height: 120)
                    .background(Color.black)

                ZStack {

                    CameraPreview(session: camera.session)
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height * 0.59
                        )
                        .clipped()

                    measurementOverlay

                    if camera.permissionDenied {
                        permissionOverlay
                    }

                    if camera.isExportingVideo {
                        exportingOverlay
                    }
                }
                .frame(height: geometry.size.height * 0.59)
                .clipped()

                VStack(spacing: 16) {

                    if showFilters {
                        filterSelectorCarousel
                    } else {
                        modeSelector
                    }

                    HStack {

                        sideButton(
                            title: "Overlays",
                            icon: "rectangle.3.group"
                        ) {
                            showOverlays = true
                        }

                        Spacer()

                        captureButton

                        Spacer()

                        sideButton(
                            title: showFilters ? "Done" : "Filters",
                            icon: showFilters ? "checkmark.circle.fill" : "camera.filters"
                        ) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showFilters.toggle()
                            }
                        }
                    }
                    .padding(.horizontal, 25)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 16)
                .padding(.bottom, 12)
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
        .onChange(of: camera.capturedImage) { _, image in
            showPhotoPreview = image != nil
        }
        .onChange(of: camera.savedVideoURL) { _, url in
            showVideoPreview = url != nil
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
            if let image = camera.capturedImage {
                MediaPhotoReview(
                    image: image,
                    onSave: camera.saveCapturedPhoto
                )
            }
        }
        .sheet(isPresented: $showVideoPreview) {
            if let url = camera.savedVideoURL {
                MediaVideoReview(
                    url: url,
                    onSave: camera.saveRecordedVideo
                )
            }
        }
        .confirmationDialog(
            "Overlays",
            isPresented: $showOverlays
        ) {
            Button(camera.overlaySettings.showSoundLevel ? "✓ Live Sound Level" : "Live Sound Level") {
                camera.overlaySettings.showSoundLevel.toggle()
            }
            Button(camera.overlaySettings.showStatistics ? "✓ Statistics (AVG/MIN/MAX/PEAK)" : "Statistics (AVG/MIN/MAX/PEAK)") {
                camera.overlaySettings.showStatistics.toggle()
            }
            Button(camera.overlaySettings.showTimestamp ? "✓ Timestamp" : "Timestamp") {
                camera.overlaySettings.showTimestamp.toggle()
            }
            Button(camera.overlaySettings.showWatermark ? "✓ Watermark (#SoundMeter)" : "Watermark (#SoundMeter)") {
                camera.overlaySettings.showWatermark.toggle()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Filter Selector Carousel UI

    private var filterSelectorCarousel: some View {
        VStack(spacing: 10) {
            HStack {
                Label("SELECT FILTER", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(cyan)
                    .tracking(1.4)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showFilters = false
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
                                        .frame(width: 48, height: 48)

                                    Image(systemName: filter.iconName)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.white)

                                    if isSelected {
                                        Circle()
                                            .stroke(cyan, lineWidth: 3)
                                            .frame(width: 56, height: 56)
                                            .shadow(color: cyan.opacity(0.6), radius: 5)
                                    }
                                }
                                .frame(width: 58, height: 58)

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

    // MARK: Top Controls

    private var topControls: some View {

        VStack {

            HStack {

                Button {
                    dismiss()
                } label: {

                    Image(systemName: "xmark")
                        .font(.system(size: 27))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Close camera")

                Spacer()

                Button {
                    camera.toggleFlash()
                } label: {

                    Image(
                        systemName: camera.isFlashEnabled
                            ? "bolt.fill"
                            : "bolt.slash"
                    )
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                }

                Button {
                    camera.switchCamera()
                } label: {

                    Image(systemName: "camera.rotate")
                        .font(.system(size: 23))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 55)

            Spacer()
        }
    }

    // MARK: Measurement Overlay

    private var measurementOverlay: some View {

        VStack {

            HStack(alignment: .top) {

                if camera.overlaySettings.showSoundLevel {
                    VStack(alignment: .leading, spacing: 4) {

                        HStack(alignment: .firstTextBaseline) {

                            Text(
                                camera.currentDBFS,
                                format: .number.precision(
                                    .fractionLength(1)
                                )
                            )
                            .font(
                                .system(
                                    size: 65,
                                    weight: .ultraLight,
                                    design: .rounded
                                )
                            )
                            .monospacedDigit()

                            Text("dBFS")
                                .font(.system(size: 20))
                        }

                        Text("LIVE SOUND LEVEL")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.2)
                    }
                } else {
                    Spacer().frame(width: 1)
                }

                Spacer()

                if camera.overlaySettings.showStatistics {
                    VStack(alignment: .trailing, spacing: 5) {

                        statistic("AVG", camera.averageDBFS)
                        statistic("MIN", camera.minimumDBFS)
                        statistic("MAX", camera.maximumDBFS)
                        statistic("PEAK", camera.peakDBFS)
                    }
                    .font(.system(size: 14))
                    .monospacedDigit()
                }
            }

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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(cyan)
                    .clipShape(Capsule())
                    .shadow(color: cyan.opacity(0.4), radius: 4)

                    Spacer()
                }
                .padding(.top, 6)
            }

            Spacer()

            HStack(alignment: .bottom) {

                if camera.overlaySettings.showWatermark {
                    Text("#SoundMeter")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(6)
                        .background(.black.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Spacer()

                if camera.overlaySettings.showTimestamp {
                    VStack(alignment: .trailing, spacing: 4) {

                        Text(
                            Date.now,
                            format: .dateTime.hour().minute()
                        )

                        Text(
                            Date.now,
                            format: .dateTime.weekday(.wide)
                                .month(.wide)
                                .day()
                                .year()
                        )
                    }
                    .font(.system(size: 12))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {

            LinearGradient(
                colors: [
                    .black.opacity(0.3),
                    .clear,
                    .black.opacity(0.45)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }

    private func statistic(
        _ title: String,
        _ value: Double
    ) -> some View {

        HStack(spacing: 5) {

            Text("\(title):")

            Text(
                value.formatted(
                    .number.precision(.fractionLength(1))
                )
            )
        }
    }

    // MARK: Permission & Export Overlays

    private var permissionOverlay: some View {

        VStack(spacing: 16) {

            Image(systemName: "mic.slash.fill")
                .font(.system(size: 44))
                .foregroundStyle(.yellow)

            Text("Camera & Microphone Access Required")
                .font(.system(size: 17, weight: .bold))

            Text("SoundMeter needs access to measure sound levels and capture photo/video.")
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
        .background(.black.opacity(0.85))
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
        .background(.black.opacity(0.85))
    }

    // MARK: Mode Selector

    private var modeSelector: some View {

        HStack(spacing: 72) {

            modeButton("PHOTO", selected: !isVideoMode) {
                isVideoMode = false
            }

            modeButton("VIDEO", selected: isVideoMode) {
                isVideoMode = true
            }
        }
    }

    private func modeButton(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {

        Button(action: action) {

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selected ? .yellow : .gray)
                .padding(.vertical, 8)
        }
        .disabled(camera.isRecording || camera.isExportingVideo)
    }

    // MARK: Capture Button

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

                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)

                if isVideoMode {

                    RoundedRectangle(
                        cornerRadius: camera.isRecording ? 4 : 35
                    )
                    .fill(.red)
                    .frame(
                        width: camera.isRecording ? 28 : 64,
                        height: camera.isRecording ? 28 : 64
                    )

                } else {

                    Circle()
                        .fill(.white)
                        .frame(width: 64, height: 64)
                }
            }
        }
        .disabled(camera.isExportingVideo)
    }

    // MARK: Side Button

    private func sideButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {

        Button(action: action) {

            VStack(spacing: 6) {

                Image(systemName: icon)
                    .font(.system(size: 21))
                    .foregroundStyle(.white)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.gray)
            }
            .frame(width: 65)
        }
        .disabled(camera.isRecording || camera.isExportingVideo)
    }
}

// MARK: Photo Review

private struct MediaPhotoReview: View {

    let image: UIImage
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSaved = false

    var body: some View {

        NavigationStack {

            ZStack {

                Color.black.ignoresSafeArea()

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {

                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {

                    Button {
                        onSave()
                        isSaved = true
                    } label: {

                        Label(
                            isSaved ? "Saved" : "Save",
                            systemImage: isSaved
                                ? "checkmark.circle.fill"
                                : "square.and.arrow.down"
                        )
                    }
                    .disabled(isSaved)
                }
            }
        }
    }
}

// MARK: Video Review

private struct MediaVideoReview: View {

    let url: URL
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSaved = false

    var body: some View {

        NavigationStack {

            ZStack {

                Color.black.ignoresSafeArea()

                VideoPlayer(player: AVPlayer(url: url))
            }
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {

                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {

                    Button {
                        onSave()
                        isSaved = true
                    } label: {

                        Label(
                            isSaved ? "Saved" : "Save",
                            systemImage: isSaved
                                ? "checkmark.circle.fill"
                                : "square.and.arrow.down"
                        )
                    }
                    .disabled(isSaved)
                }
            }
        }
    }
}

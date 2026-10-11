import Foundation
import AVFoundation
import Photos
import UIKit
import Combine
import CoreImage
import CoreLocation
import SwiftUI

// MARK: - Models & Enums

struct OverlaySettings: Equatable, Codable {
    var showSoundLevel: Bool = true
    var showAverage: Bool = true
    var showMinimum: Bool = true
    var showMaximum: Bool = true
    var showPeak: Bool = true
    var showDuration: Bool = true
    var showTimestamp: Bool = true
    var showLocation: Bool = false
    var showWatermark: Bool = true
    var useAcousticScale: Bool = true

    var showStatistics: Bool {
        showAverage || showMinimum || showMaximum || showPeak
    }

    private static let userDefaultsKey = "com.soundmeter.overlaySettings.v2"

    static func load() -> OverlaySettings {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let settings = try? JSONDecoder().decode(OverlaySettings.self, from: data) {
            return settings
        }
        return OverlaySettings()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: OverlaySettings.userDefaultsKey)
        }
    }
}

enum CameraAspectRatio: String, CaseIterable, Identifiable, Codable {
    case ratio4_3 = "4:3"
    case ratio16_9 = "16:9"
    case ratio1_1 = "1:1"

    var id: String { rawValue }

    var widthRatio: CGFloat {
        switch self {
        case .ratio4_3: return 3.0 / 4.0
        case .ratio16_9: return 9.0 / 16.0
        case .ratio1_1: return 1.0
        }
    }

    var heightMultiplier: CGFloat {
        switch self {
        case .ratio4_3: return 4.0 / 3.0
        case .ratio16_9: return 16.0 / 9.0
        case .ratio1_1: return 1.0
        }
    }
}

enum CameraFlashMode: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case on = "On"
    case off = "Off"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .auto: return "bolt.badge.automatic"
        case .on: return "bolt.fill"
        case .off: return "bolt.slash.fill"
        }
    }
}

enum CameraFilter: String, CaseIterable, Identifiable, Codable {
    case original = "Original"
    case mono = "Black & White"
    case sepia = "Sepia"
    case noir = "Noir"
    case vintage = "Vintage"
    case chrome = "Chrome"

    var id: String { rawValue }

    var ciFilterName: String? {
        switch self {
        case .original:
            return nil
        case .mono:
            return "CIPhotoEffectMono"
        case .sepia:
            return "CISepiaTone"
        case .noir:
            return "CIPhotoEffectNoir"
        case .vintage:
            return "CIPhotoEffectTransfer"
        case .chrome:
            return "CIPhotoEffectChrome"
        }
    }

    var iconName: String {
        switch self {
        case .original: return "sparkles"
        case .mono: return "circle.lefthalf.filled"
        case .sepia: return "sun.amber.fill"
        case .noir: return "moon.stars.fill"
        case .vintage: return "camera.filters"
        case .chrome: return "slider.horizontal.2.square"
        }
    }

    var subtitle: String {
        switch self {
        case .original: return "Natural"
        case .mono: return "B&W"
        case .sepia: return "Warm Sepia"
        case .noir: return "Noir Dark"
        case .vintage: return "Retro Vintage"
        case .chrome: return "Cool Chrome"
        }
    }

    var previewGradient: [Color] {
        switch self {
        case .original:
            return [Color.cyan, Color.blue]
        case .mono:
            return [Color.gray, Color.white.opacity(0.8), Color.black]
        case .sepia:
            return [Color.orange, Color.yellow, Color.brown]
        case .noir:
            return [Color.black, Color.gray.opacity(0.6), Color.black]
        case .vintage:
            return [Color.purple.opacity(0.8), Color.orange.opacity(0.8), Color.teal.opacity(0.8)]
        case .chrome:
            return [Color.blue.opacity(0.8), Color.cyan, Color.white.opacity(0.8)]
        }
    }
}

struct SoundSnapshot: Equatable, Sendable {
    let timeOffset: TimeInterval
    let currentDBFS: Double
    let currentAcousticDB: Double
    let averageDBFS: Double
    let averageAcousticDB: Double
    let minimumDBFS: Double
    let minimumAcousticDB: Double
    let maximumDBFS: Double
    let maximumAcousticDB: Double
    let peakDBFS: Double
    let peakAcousticDB: Double
    let durationFormatted: String
    let timestamp: Date
}

enum CameraServiceError: LocalizedError {
    case cameraUnavailable
    case permissionDenied
    case photoDataUnavailable
    case recordingFailed
    case torchUnavailable
    case videoExportFailed

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "No compatible camera is available."
        case .permissionDenied:
            return "Camera and microphone permissions are required to use this feature."
        case .photoDataUnavailable:
            return "The captured photo could not be processed."
        case .recordingFailed:
            return "The video recording could not be completed."
        case .torchUnavailable:
            return "Flash is unavailable on this camera."
        case .videoExportFailed:
            return "Failed to process video with sound level overlay."
        }
    }
}

// MARK: - Location Manager

final class CameraLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var locationName: String?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let clManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var isRequesting = false

    override init() {
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = clManager.authorizationStatus
    }

    func requestPermissionIfNeeded() {
        let status = clManager.authorizationStatus
        if status == .notDetermined {
            clManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            fetchLocation()
        }
    }

    func fetchLocation() {
        guard !isRequesting else { return }
        isRequesting = true
        clManager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
        }
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            fetchLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        isRequesting = false
        guard let location = locations.last else { return }

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self, let place = placemarks?.first else { return }
            var components: [String] = []
            if let locality = place.locality {
                components.append(locality)
            }
            if let state = place.administrativeArea {
                components.append(state)
            } else if let country = place.country {
                components.append(country)
            }
            let name = components.joined(separator: ", ")
            DispatchQueue.main.async {
                self.locationName = name.isEmpty ? nil : name
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isRequesting = false
    }
}

// MARK: - Overlay Renderer

enum OverlayRenderer {

    static func cropImageToAspectRatio(_ image: UIImage, targetRatio: CameraAspectRatio) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        let isPortrait = height >= width
        let desiredRatio: CGFloat = isPortrait ? targetRatio.widthRatio : (1.0 / targetRatio.widthRatio)
        let currentRatio = width / height

        if abs(currentRatio - desiredRatio) < 0.02 {
            return image
        }

        var newWidth = width
        var newHeight = height

        if currentRatio > desiredRatio {
            newWidth = height * desiredRatio
        } else {
            newHeight = width / desiredRatio
        }

        let originX = (width - newWidth) / 2.0
        let originY = (height - newHeight) / 2.0
        let cropRect = CGRect(x: originX, y: originY, width: newWidth, height: newHeight)

        guard let croppedCG = cgImage.cropping(to: cropRect) else {
            return image
        }

        return UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)
    }

    static func processCapturedPhoto(
        image: UIImage,
        aspectRatio: CameraAspectRatio,
        currentDBFS: Double,
        currentAcousticDB: Double,
        averageDBFS: Double,
        averageAcousticDB: Double,
        minimumDBFS: Double,
        minimumAcousticDB: Double,
        maximumDBFS: Double,
        maximumAcousticDB: Double,
        peakDBFS: Double,
        peakAcousticDB: Double,
        durationFormatted: String,
        locationName: String?,
        filter: CameraFilter,
        settings: OverlaySettings,
        timestamp: Date = Date()
    ) -> (annotated: UIImage, raw: UIImage) {

        let croppedImage = cropImageToAspectRatio(image, targetRatio: aspectRatio)
        var filteredImage = croppedImage

        if let ciFilterName = filter.ciFilterName,
           let ciImage = CIImage(image: croppedImage) ?? croppedImage.ciImage {
            let context = CIContext()
            if let filterObj = CIFilter(name: ciFilterName) {
                filterObj.setValue(ciImage, forKey: kCIInputImageKey)
                if let outputCI = filterObj.outputImage,
                   let cgImage = context.createCGImage(outputCI, from: outputCI.extent) {
                    filteredImage = UIImage(cgImage: cgImage, scale: croppedImage.scale, orientation: croppedImage.imageOrientation)
                }
            }
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = filteredImage.scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: filteredImage.size, format: format)

        let annotatedImage = renderer.image { context in
            let cgContext = context.cgContext
            let bounds = CGRect(origin: .zero, size: filteredImage.size)

            filteredImage.draw(in: bounds)

            drawOverlay(
                in: cgContext,
                bounds: bounds,
                currentDBFS: currentDBFS,
                currentAcousticDB: currentAcousticDB,
                averageDBFS: averageDBFS,
                averageAcousticDB: averageAcousticDB,
                minimumDBFS: minimumDBFS,
                minimumAcousticDB: minimumAcousticDB,
                maximumDBFS: maximumDBFS,
                maximumAcousticDB: maximumAcousticDB,
                peakDBFS: peakDBFS,
                peakAcousticDB: peakAcousticDB,
                durationFormatted: durationFormatted,
                locationName: locationName,
                filter: filter,
                settings: settings,
                timestamp: timestamp
            )
        }

        return (annotated: annotatedImage, raw: filteredImage)
    }

    static func drawOverlay(
        in context: CGContext,
        bounds: CGRect,
        currentDBFS: Double,
        currentAcousticDB: Double,
        averageDBFS: Double,
        averageAcousticDB: Double,
        minimumDBFS: Double,
        minimumAcousticDB: Double,
        maximumDBFS: Double,
        maximumAcousticDB: Double,
        peakDBFS: Double,
        peakAcousticDB: Double,
        durationFormatted: String,
        locationName: String?,
        filter: CameraFilter,
        settings: OverlaySettings,
        timestamp: Date
    ) {
        let width = bounds.width
        let height = bounds.height
        guard width > 0 && height > 0 else { return }

        let scale = max(0.4, min(width, height) / 400.0)
        let padding = 16.0 * scale

        context.saveGState()

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let topGradientColors = [
            UIColor.black.withAlphaComponent(0.45).cgColor,
            UIColor.clear.cgColor
        ] as CFArray
        if let topGradient = CGGradient(colorsSpace: colorSpace, colors: topGradientColors, locations: [0.0, 1.0]) {
            context.drawLinearGradient(
                topGradient,
                start: CGPoint(x: width / 2, y: 0),
                end: CGPoint(x: width / 2, y: height * 0.25),
                options: []
            )
        }

        let bottomGradientColors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.55).cgColor
        ] as CFArray
        if let bottomGradient = CGGradient(colorsSpace: colorSpace, colors: bottomGradientColors, locations: [0.0, 1.0]) {
            context.drawLinearGradient(
                bottomGradient,
                start: CGPoint(x: width / 2, y: height * 0.75),
                end: CGPoint(x: width / 2, y: height),
                options: []
            )
        }

        let savedWeighting = UserDefaults.standard.string(forKey: "defaultWeighting") ?? "A"
        let weightingUnit = FrequencyWeighting(rawValue: savedWeighting)?.unitSymbol ?? "dBA"

        if settings.showSoundLevel {
            let displayVal = settings.useAcousticScale ? currentAcousticDB : currentDBFS
            let unitString = settings.useAcousticScale ? weightingUnit : "dBFS"
            let dbValueString = String(format: "%.1f", displayVal)

            let largeFont = UIFont.systemFont(ofSize: 52.0 * scale, weight: .ultraLight)
            let unitFont = UIFont.systemFont(ofSize: 18.0 * scale, weight: .regular)
            let subtitleFont = UIFont.systemFont(ofSize: 10.0 * scale, weight: .semibold)

            let numberAttrs: [NSAttributedString.Key: Any] = [
                .font: largeFont,
                .foregroundColor: UIColor.white
            ]
            let unitAttrs: [NSAttributedString.Key: Any] = [
                .font: unitFont,
                .foregroundColor: UIColor.white
            ]
            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: subtitleFont,
                .foregroundColor: UIColor.white,
                .kern: 1.2 * scale
            ]

            let numberSize = (dbValueString as NSString).size(withAttributes: numberAttrs)
            let unitSize = (unitString as NSString).size(withAttributes: unitAttrs)

            let dbX = padding
            let dbY = padding

            (dbValueString as NSString).draw(at: CGPoint(x: dbX, y: dbY), withAttributes: numberAttrs)
            (unitString as NSString).draw(
                at: CGPoint(x: dbX + numberSize.width + (4.0 * scale), y: dbY + numberSize.height - unitSize.height - (4.0 * scale)),
                withAttributes: unitAttrs
            )

            let subY = dbY + numberSize.height + (2.0 * scale)
            ("LIVE SOUND LEVEL" as NSString).draw(at: CGPoint(x: dbX, y: subY), withAttributes: subtitleAttrs)
        }

        if settings.showStatistics {
            let statFont = UIFont.monospacedSystemFont(ofSize: 13.0 * scale, weight: .regular)
            let statAttrs: [NSAttributedString.Key: Any] = [
                .font: statFont,
                .foregroundColor: UIColor.white
            ]

            var lines: [String] = []
            if settings.showAverage {
                let v = settings.useAcousticScale ? averageAcousticDB : averageDBFS
                lines.append(String(format: "AVG: %.1f", v))
            }
            if settings.showMinimum {
                let v = settings.useAcousticScale ? minimumAcousticDB : minimumDBFS
                lines.append(String(format: "MIN: %.1f", v))
            }
            if settings.showMaximum {
                let v = settings.useAcousticScale ? maximumAcousticDB : maximumDBFS
                lines.append(String(format: "MAX: %.1f", v))
            }
            if settings.showPeak {
                let v = settings.useAcousticScale ? peakAcousticDB : peakDBFS
                lines.append(String(format: "PEAK: %.1f", v))
            }

            var currentY = padding
            for line in lines {
                let size = (line as NSString).size(withAttributes: statAttrs)
                let xPos = width - padding - size.width
                (line as NSString).draw(at: CGPoint(x: xPos, y: currentY), withAttributes: statAttrs)
                currentY += size.height + (3.0 * scale)
            }
        }

        if settings.showWatermark {
            let watermarkFont = UIFont.systemFont(ofSize: 11.0 * scale, weight: .semibold)
            let watermarkAttrs: [NSAttributedString.Key: Any] = [
                .font: watermarkFont,
                .foregroundColor: UIColor.white
            ]
            let text = "#SoundMeter"
            let textSize = (text as NSString).size(withAttributes: watermarkAttrs)
            let margin = 6.0 * scale
            let boxRect = CGRect(
                x: padding,
                y: height - padding - textSize.height - (margin * 2),
                width: textSize.width + (margin * 2),
                height: textSize.height + (margin * 2)
            )

            let path = UIBezierPath(roundedRect: boxRect, cornerRadius: 4.0 * scale)
            context.setFillColor(UIColor.black.withAlphaComponent(0.45).cgColor)
            context.addPath(path.cgPath)
            context.fillPath()

            (text as NSString).draw(
                at: CGPoint(x: boxRect.origin.x + margin, y: boxRect.origin.y + margin),
                withAttributes: watermarkAttrs
            )
        }

        var bottomTrailingY = height - padding

        if settings.showTimestamp {
            let timeFont = UIFont.systemFont(ofSize: 12.0 * scale, weight: .medium)
            let dateFont = UIFont.systemFont(ofSize: 11.0 * scale, weight: .regular)

            let timeFormatter = DateFormatter()
            timeFormatter.dateStyle = .none
            timeFormatter.timeStyle = .short
            let timeStr = timeFormatter.string(from: timestamp)

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEEE, MMMM d, yyyy"
            let dateStr = dateFormatter.string(from: timestamp)

            let timeAttrs: [NSAttributedString.Key: Any] = [
                .font: timeFont,
                .foregroundColor: UIColor.white
            ]
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: dateFont,
                .foregroundColor: UIColor.white
            ]

            let timeSize = (timeStr as NSString).size(withAttributes: timeAttrs)
            let dateSize = (dateStr as NSString).size(withAttributes: dateAttrs)

            let dateX = width - padding - dateSize.width
            bottomTrailingY -= dateSize.height
            (dateStr as NSString).draw(at: CGPoint(x: dateX, y: bottomTrailingY), withAttributes: dateAttrs)

            bottomTrailingY -= (timeSize.height + (2.0 * scale))
            let timeX = width - padding - timeSize.width
            (timeStr as NSString).draw(at: CGPoint(x: timeX, y: bottomTrailingY), withAttributes: timeAttrs)
        }

        if settings.showLocation, let loc = locationName, !loc.isEmpty {
            let locFont = UIFont.systemFont(ofSize: 11.0 * scale, weight: .medium)
            let locAttrs: [NSAttributedString.Key: Any] = [
                .font: locFont,
                .foregroundColor: UIColor(red: 0.0, green: 0.78, blue: 0.98, alpha: 1.0)
            ]
            let locStr = "📍 \(loc)"
            let locSize = (locStr as NSString).size(withAttributes: locAttrs)
            bottomTrailingY -= (locSize.height + (4.0 * scale))
            let locX = width - padding - locSize.width
            (locStr as NSString).draw(at: CGPoint(x: locX, y: bottomTrailingY), withAttributes: locAttrs)
        }

        if settings.showDuration && !durationFormatted.isEmpty {
            let durFont = UIFont.monospacedSystemFont(ofSize: 11.0 * scale, weight: .semibold)
            let durAttrs: [NSAttributedString.Key: Any] = [
                .font: durFont,
                .foregroundColor: UIColor.white
            ]
            let durStr = "REC \(durationFormatted)"
            let durSize = (durStr as NSString).size(withAttributes: durAttrs)
            bottomTrailingY -= (durSize.height + (4.0 * scale))
            let durX = width - padding - durSize.width
            (durStr as NSString).draw(at: CGPoint(x: durX, y: bottomTrailingY), withAttributes: durAttrs)
        }

        context.restoreGState()
    }
}

// MARK: - Video Overlay Exporter

final class VideoOverlayExporter {

    enum ExportError: LocalizedError {
        case invalidInputTrack
        case assetReaderFailed
        case assetWriterFailed

        var errorDescription: String? {
            switch self {
            case .invalidInputTrack:
                return "The recorded video track is missing or invalid."
            case .assetReaderFailed:
                return "Failed to read recorded video samples."
            case .assetWriterFailed:
                return "Failed to export video with sound overlays."
            }
        }
    }

    static func exportVideo(
        inputURL: URL,
        outputURL: URL,
        snapshots: [SoundSnapshot],
        filter: CameraFilter,
        overlaySettings: OverlaySettings,
        recordingStartDate: Date,
        locationName: String?,
        progress: ((Double) -> Void)? = nil,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let asset = AVAsset(url: inputURL)

                guard let videoTrack = asset.tracks(withMediaType: .video).first else {
                    throw ExportError.invalidInputTrack
                }

                let audioTrack = asset.tracks(withMediaType: .audio).first
                let duration = CMTimeGetSeconds(asset.duration)

                let reader = try AVAssetReader(asset: asset)

                let videoReaderSettings: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                ]
                let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoReaderSettings)
                videoOutput.alwaysCopiesSampleData = false
                if reader.canAdd(videoOutput) {
                    reader.add(videoOutput)
                }

                var audioOutput: AVAssetReaderTrackOutput?
                if let audioTrack {
                    let aOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
                    aOutput.alwaysCopiesSampleData = false
                    if reader.canAdd(aOutput) {
                        reader.add(aOutput)
                        audioOutput = aOutput
                    }
                }

                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try? FileManager.default.removeItem(at: outputURL)
                }

                let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

                let naturalSize = videoTrack.naturalSize
                let transform = videoTrack.preferredTransform
                let isPortrait = (transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0) ||
                                 (transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0)
                let renderWidth = isPortrait ? Int(naturalSize.height) : Int(naturalSize.width)
                let renderHeight = isPortrait ? Int(naturalSize.width) : Int(naturalSize.height)

                let videoWriterSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: renderWidth,
                    AVVideoHeightKey: renderHeight
                ]

                let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoWriterSettings)
                videoInput.expectsMediaDataInRealTime = false

                let pixelBufferAttributes: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                    kCVPixelBufferWidthKey as String: renderWidth,
                    kCVPixelBufferHeightKey as String: renderHeight
                ]

                let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: videoInput,
                    sourcePixelBufferAttributes: pixelBufferAttributes
                )

                if writer.canAdd(videoInput) {
                    writer.add(videoInput)
                }

                var audioInput: AVAssetWriterInput?
                if audioTrack != nil {
                    let audioWriterSettings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatMPEG4AAC,
                        AVNumberOfChannelsKey: 2,
                        AVSampleRateKey: 44100.0,
                        AVEncoderBitRateKey: 128000
                    ]
                    let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioWriterSettings)
                    aInput.expectsMediaDataInRealTime = false
                    if writer.canAdd(aInput) {
                        writer.add(aInput)
                        audioInput = aInput
                    }
                }

                guard reader.startReading(), writer.startWriting() else {
                    throw ExportError.assetWriterFailed
                }

                writer.startSession(atSourceTime: .zero)

                let ciContext = CIContext()
                var bufferPool: CVPixelBufferPool?

                CVPixelBufferPoolCreate(
                    kCFAllocatorDefault,
                    nil,
                    pixelBufferAttributes as CFDictionary,
                    &bufferPool
                )

                var isVideoDone = false
                var isAudioDone = audioInput == nil

                let queue = DispatchQueue(label: "com.soundmeter.videoexporter")

                videoInput.requestMediaDataWhenReady(on: queue) {
                    while videoInput.isReadyForMoreMediaData {
                        guard let sampleBuffer = videoOutput.copyNextSampleBuffer() else {
                            if !isVideoDone {
                                isVideoDone = true
                                videoInput.markAsFinished()
                            }
                            break
                        }

                        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        let timeInSeconds = CMTimeGetSeconds(presentationTime)

                        if duration > 0 {
                            let prog = min(1.0, max(0.0, timeInSeconds / duration))
                            DispatchQueue.main.async { progress?(prog) }
                        }

                        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                            continue
                        }

                        var renderedPixelBuffer: CVPixelBuffer?
                        if let pool = bufferPool {
                            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &renderedPixelBuffer)
                        }

                        guard let destinationBuffer = renderedPixelBuffer else {
                            continue
                        }

                        var ciImage = CIImage(cvPixelBuffer: imageBuffer).oriented(forExifOrientation: Int32(self.exifOrientation(from: transform).rawValue))

                        if let ciFilterName = filter.ciFilterName,
                           let filterObj = CIFilter(name: ciFilterName) {
                            filterObj.setValue(ciImage, forKey: kCIInputImageKey)
                            if let out = filterObj.outputImage {
                                ciImage = out
                            }
                        }

                        ciContext.render(ciImage, to: destinationBuffer)

                        CVPixelBufferLockBaseAddress(destinationBuffer, [])
                        if let baseAddress = CVPixelBufferGetBaseAddress(destinationBuffer) {
                            let bytesPerRow = CVPixelBufferGetBytesPerRow(destinationBuffer)
                            let colorSpace = CGColorSpaceCreateDeviceRGB()

                            if let cgContext = CGContext(
                                data: baseAddress,
                                width: renderWidth,
                                height: renderHeight,
                                bitsPerComponent: 8,
                                bytesPerRow: bytesPerRow,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                            ) {
                                let snapshot = self.findSnapshot(at: timeInSeconds, in: snapshots)
                                let frameDate = recordingStartDate.addingTimeInterval(timeInSeconds)
                                let minutes = Int(timeInSeconds) / 60
                                let seconds = Int(timeInSeconds) % 60
                                let tenths = Int((timeInSeconds.truncatingRemainder(dividingBy: 1.0)) * 10)
                                let durationStr = String(format: "%02d:%02d.%01d", minutes, seconds, tenths)

                                OverlayRenderer.drawOverlay(
                                    in: cgContext,
                                    bounds: CGRect(x: 0, y: 0, width: renderWidth, height: renderHeight),
                                    currentDBFS: snapshot?.currentDBFS ?? -120.0,
                                    currentAcousticDB: snapshot?.currentAcousticDB ?? 30.0,
                                    averageDBFS: snapshot?.averageDBFS ?? -120.0,
                                    averageAcousticDB: snapshot?.averageAcousticDB ?? 30.0,
                                    minimumDBFS: snapshot?.minimumDBFS ?? -120.0,
                                    minimumAcousticDB: snapshot?.minimumAcousticDB ?? 30.0,
                                    maximumDBFS: snapshot?.maximumDBFS ?? -120.0,
                                    maximumAcousticDB: snapshot?.maximumAcousticDB ?? 30.0,
                                    peakDBFS: snapshot?.peakDBFS ?? -120.0,
                                    peakAcousticDB: snapshot?.peakAcousticDB ?? 30.0,
                                    durationFormatted: durationStr,
                                    locationName: locationName,
                                    filter: filter,
                                    settings: overlaySettings,
                                    timestamp: frameDate
                                )
                            }
                        }
                        CVPixelBufferUnlockBaseAddress(destinationBuffer, [])

                        adaptor.append(destinationBuffer, withPresentationTime: presentationTime)
                    }
                }

                if let audioInput, let audioOutput {
                    audioInput.requestMediaDataWhenReady(on: queue) {
                        while audioInput.isReadyForMoreMediaData {
                            guard let sampleBuffer = audioOutput.copyNextSampleBuffer() else {
                                if !isAudioDone {
                                    isAudioDone = true
                                    audioInput.markAsFinished()
                                }
                                break
                            }
                            audioInput.append(sampleBuffer)
                        }
                    }
                }

                while !isVideoDone || !isAudioDone {
                    Thread.sleep(forTimeInterval: 0.05)
                }

                writer.finishWriting {
                    if writer.status == .completed {
                        DispatchQueue.main.async {
                            completion(.success(outputURL))
                        }
                    } else {
                        DispatchQueue.main.async {
                            completion(.failure(writer.error ?? ExportError.assetWriterFailed))
                        }
                    }
                }

            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    private static func findSnapshot(at timeOffset: TimeInterval, in snapshots: [SoundSnapshot]) -> SoundSnapshot? {
        guard !snapshots.isEmpty else { return nil }
        if timeOffset <= (snapshots.first?.timeOffset ?? 0) { return snapshots.first }
        if timeOffset >= (snapshots.last?.timeOffset ?? 0) { return snapshots.last }

        for i in 0..<(snapshots.count - 1) {
            if timeOffset >= snapshots[i].timeOffset && timeOffset <= snapshots[i + 1].timeOffset {
                let d1 = abs(timeOffset - snapshots[i].timeOffset)
                let d2 = abs(timeOffset - snapshots[i + 1].timeOffset)
                return d1 < d2 ? snapshots[i] : snapshots[i + 1]
            }
        }
        return snapshots.last
    }

    private static func exifOrientation(from transform: CGAffineTransform) -> CGImagePropertyOrientation {
        if transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0 {
            return .right
        } else if transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0 {
            return .left
        } else if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
            return .down
        } else {
            return .up
        }
    }
}

// MARK: - Camera Service Main Class

final class CameraService: NSObject, ObservableObject {

    // MARK: - Camera & Session State

    let session = AVCaptureSession()

    @Published private(set) var isConfigured = false
    @Published private(set) var isRecording = false
    @Published private(set) var recordingDuration: TimeInterval = 0.0
    @Published private(set) var isExportingVideo = false
    @Published private(set) var exportProgress: Double = 0.0
    @Published private(set) var flashMode: CameraFlashMode = .auto
    @Published private(set) var isFlashAvailable = true
    @Published private(set) var isUsingFrontCamera = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var isInterrupted = false

    @Published var aspectRatio: CameraAspectRatio = .ratio4_3
    @Published var selectedFilter: CameraFilter = .original
    @Published var overlaySettings: OverlaySettings = OverlaySettings.load() {
        didSet {
            overlaySettings.save()
        }
    }

    @Published var capturedAnnotatedImage: UIImage?
    @Published var capturedRawImage: UIImage?
    @Published var savedVideoURL: URL?
    @Published var errorMessage: String?

    // MARK: - Location & Sound Measurements

    @Published var locationService = CameraLocationManager()

    @Published private(set) var currentDBFS: Double = -120.0
    @Published private(set) var currentAcousticDB: Double = 30.0
    @Published private(set) var averageDBFS: Double = -120.0
    @Published private(set) var averageAcousticDB: Double = 30.0
    @Published private(set) var minimumDBFS: Double = -120.0
    @Published private(set) var minimumAcousticDB: Double = 30.0
    @Published private(set) var maximumDBFS: Double = -120.0
    @Published private(set) var maximumAcousticDB: Double = 30.0
    @Published private(set) var peakDBFS: Double = -120.0
    @Published private(set) var peakAcousticDB: Double = 30.0

    // MARK: - Audio Engine Integration

    private let audioCaptureService = AudioCaptureService()
    private var audioCaptureTask: Task<Void, Never>?

    // MARK: - Capture Components & Queues

    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()

    private let sessionQueue = DispatchQueue(
        label: "com.soundmeter.camera.session"
    )

    private var isSessionRunning = false
    private var isConfiguring = false
    private var internalIsConfigured = false

    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    private var measurements: [Double] = []
    private var recordedSnapshots: [SoundSnapshot] = []
    private var recordingStartDate: Date?
    private var recordingTimer: Timer?

    private var videoOutputURL: URL?
    private let maximumMeasurementCount = 3600

    var recordingDurationFormatted: String {
        let total = recordingDuration
        let minutes = Int(total) / 60
        let seconds = Int(total) % 60
        let tenths = Int((total.truncatingRemainder(dividingBy: 1.0)) * 10)
        return String(format: "%02d:%02d.%01d", minutes, seconds, tenths)
    }

    override init() {
        super.init()
        setupAudioCapture()
        setupInterruptionObservers()
    }

    private func setupAudioCapture() {
        let savedWeighting = UserDefaults.standard.string(forKey: "defaultWeighting") ?? "A"
        audioCaptureService.weighting = FrequencyWeighting(rawValue: savedWeighting) ?? .a
        audioCaptureService.onLevel = { [weak self] level, _ in
            self?.updateSoundLevel(level)
        }
    }

    private func setupInterruptionObservers() {
        NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.isInterrupted = true
        }

        NotificationCenter.default.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.isInterrupted = false
        }
    }

    // MARK: - Permission & Life Cycle

    func prepare() {
        requestPermissions { [weak self] granted in
            guard let self else { return }

            guard granted else {
                DispatchQueue.main.async {
                    self.permissionDenied = true
                }
                self.publishError(CameraServiceError.permissionDenied)
                return
            }

            DispatchQueue.main.async {
                self.permissionDenied = false
            }

            self.sessionQueue.async {
                self.configureSessionIfNeeded()
            }
        }
    }

    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()

        var cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        var microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        if cameraStatus == .notDetermined {
            group.enter()
            AVCaptureDevice.requestAccess(for: .video) { granted in
                lock.lock()
                cameraGranted = granted
                lock.unlock()
                group.leave()
            }
        }

        if microphoneStatus == .notDetermined {
            group.enter()
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                lock.lock()
                microphoneGranted = granted
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            lock.lock()
            let granted = cameraGranted && microphoneGranted
            lock.unlock()
            completion(granted)
        }
    }

    // MARK: - Session Configuration

    private func configureSessionIfNeeded() {
        guard !internalIsConfigured, !isConfiguring else {
            if internalIsConfigured {
                startSessionIfNeeded()
            }
            return
        }

        isConfiguring = true
        session.beginConfiguration()

        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            session.commitConfiguration()
            isConfiguring = false
            publishError(CameraServiceError.cameraUnavailable)
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                isConfiguring = false
                publishError(CameraServiceError.cameraUnavailable)
                return
            }
            session.addInput(input)
            videoInput = input
        } catch {
            session.commitConfiguration()
            isConfiguring = false
            publishError(error)
            return
        }

        if let microphone = AVCaptureDevice.default(for: .audio) {
            do {
                let input = try AVCaptureDeviceInput(device: microphone)
                if session.canAddInput(input) {
                    session.addInput(input)
                    audioInput = input
                }
            } catch {
                publishError(error)
            }
        }

        guard session.canAddOutput(photoOutput),
              session.canAddOutput(movieOutput) else {
            session.commitConfiguration()
            isConfiguring = false
            publishError(CameraServiceError.cameraUnavailable)
            return
        }

        session.addOutput(photoOutput)
        session.addOutput(movieOutput)

        session.commitConfiguration()
        isConfiguring = false
        internalIsConfigured = true

        DispatchQueue.main.async {
            self.isConfigured = true
            self.isFlashAvailable = device.hasFlash
        }

        startSessionIfNeeded()
    }

    // MARK: - Start / Stop Session & Audio

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if !self.internalIsConfigured {
                self.configureSessionIfNeeded()
                return
            }

            self.startSessionIfNeeded()
        }

        audioCaptureTask?.cancel()
        audioCaptureTask = Task { [weak self] in
            guard let self else { return }
            let saved = UserDefaults.standard.string(forKey: "defaultWeighting") ?? "A"
            self.audioCaptureService.weighting = FrequencyWeighting(rawValue: saved) ?? .a
            guard !Task.isCancelled else { return }
            try? await self.audioCaptureService.start()
        }

        if overlaySettings.showLocation {
            locationService.requestPermissionIfNeeded()
        }
    }

    private func startSessionIfNeeded() {
        guard internalIsConfigured else { return }
        guard !isSessionRunning else { return }

        if !session.isRunning {
            session.startRunning()
        }
        isSessionRunning = session.isRunning
    }

    func stop() {
        audioCaptureTask?.cancel()
        audioCaptureTask = nil
        audioCaptureService.stop()
        stopRecordingTimer()

        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }

            if self.session.isRunning {
                self.session.stopRunning()
            }

            self.isSessionRunning = false
        }
    }

    deinit {
        audioCaptureTask?.cancel()
        audioCaptureService.stop()
        stopRecordingTimer()
        if session.isRunning {
            session.stopRunning()
        }
    }

    // MARK: - Sound Measurements Calculation

    func updateSoundLevel(_ level: Double) {
        guard level.isFinite else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let offset = UserDefaults.standard.double(forKey: "microphoneGainOffset")
            let acoustic = max(20.0, min(130.0, level + 100.0 + offset))

            self.currentDBFS = level
            self.currentAcousticDB = acoustic
            self.measurements.append(level)

            if self.measurements.count > self.maximumMeasurementCount {
                self.measurements.removeFirst(
                    self.measurements.count - self.maximumMeasurementCount
                )
            }

            guard !self.measurements.isEmpty else { return }

            let avgDBFS = SoundLevelCalculator.energyAverageDBFS(self.measurements)
            self.averageDBFS = avgDBFS
            self.averageAcousticDB = max(20.0, min(130.0, avgDBFS + 100.0 + offset))

            if self.minimumDBFS == -120.0 {
                self.minimumDBFS = level
                self.minimumAcousticDB = acoustic
            } else {
                self.minimumDBFS = min(self.minimumDBFS, level)
                self.minimumAcousticDB = min(self.minimumAcousticDB, acoustic)
            }

            if self.maximumDBFS == -120.0 {
                self.maximumDBFS = level
                self.maximumAcousticDB = acoustic
            } else {
                self.maximumDBFS = max(self.maximumDBFS, level)
                self.maximumAcousticDB = max(self.maximumAcousticDB, acoustic)
            }

            if self.peakDBFS == -120.0 {
                self.peakDBFS = level
                self.peakAcousticDB = acoustic
            } else {
                self.peakDBFS = max(self.peakDBFS, level)
                self.peakAcousticDB = max(self.peakAcousticDB, acoustic)
            }

            if self.isRecording, let startDate = self.recordingStartDate {
                let timeOffset = Date.now.timeIntervalSince(startDate)
                let snapshot = SoundSnapshot(
                    timeOffset: timeOffset,
                    currentDBFS: self.currentDBFS,
                    currentAcousticDB: self.currentAcousticDB,
                    averageDBFS: self.averageDBFS,
                    averageAcousticDB: self.averageAcousticDB,
                    minimumDBFS: self.minimumDBFS,
                    minimumAcousticDB: self.minimumAcousticDB,
                    maximumDBFS: self.maximumDBFS,
                    maximumAcousticDB: self.maximumAcousticDB,
                    peakDBFS: self.peakDBFS,
                    peakAcousticDB: self.peakAcousticDB,
                    durationFormatted: self.recordingDurationFormatted,
                    timestamp: Date.now
                )
                self.recordedSnapshots.append(snapshot)
            }
        }
    }

    func resetMeasurements() {
        DispatchQueue.main.async {
            self.measurements.removeAll()
            self.currentDBFS = -120.0
            self.currentAcousticDB = 30.0
            self.averageDBFS = -120.0
            self.averageAcousticDB = 30.0
            self.minimumDBFS = -120.0
            self.minimumAcousticDB = 30.0
            self.maximumDBFS = -120.0
            self.maximumAcousticDB = 30.0
            self.peakDBFS = -120.0
            self.peakAcousticDB = 30.0
        }
    }

    // MARK: - Photo Capture

    func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self,
                  self.internalIsConfigured,
                  self.session.isRunning else {
                self?.publishError(CameraServiceError.cameraUnavailable)
                return
            }

            let settings = AVCapturePhotoSettings()

            if let input = self.videoInput, input.device.hasFlash {
                switch self.flashMode {
                case .auto:
                    if self.photoOutput.supportedFlashModes.contains(.auto) {
                        settings.flashMode = .auto
                    }
                case .on:
                    if self.photoOutput.supportedFlashModes.contains(.on) {
                        settings.flashMode = .on
                    }
                case .off:
                    settings.flashMode = .off
                }
            } else {
                settings.flashMode = .off
            }

            self.photoOutput.capturePhoto(
                with: settings,
                delegate: self
            )
        }
    }

    // MARK: - Video Recording

    func startRecording() {
        sessionQueue.async { [weak self] in
            guard let self,
                  self.internalIsConfigured,
                  self.session.isRunning,
                  !self.movieOutput.isRecording else {
                return
            }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("SoundMeter-raw-\(UUID().uuidString).mov")

            self.videoOutputURL = url

            if let input = self.videoInput, input.device.hasTorch, self.flashMode == .on {
                try? input.device.lockForConfiguration()
                try? input.device.setTorchModeOn(level: 1.0)
                input.device.unlockForConfiguration()
            }

            DispatchQueue.main.async {
                self.recordedSnapshots.removeAll()
                self.recordingStartDate = Date()
                self.recordingDuration = 0.0
                self.isRecording = true
                self.startRecordingTimer()
            }

            self.movieOutput.startRecording(
                to: url,
                recordingDelegate: self
            )
        }
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self, self.movieOutput.isRecording else { return }

            if let input = self.videoInput, input.device.hasTorch, input.device.torchMode == .on {
                try? input.device.lockForConfiguration()
                input.device.torchMode = .off
                input.device.unlockForConfiguration()
            }

            self.movieOutput.stopRecording()
        }
    }

    private func startRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartDate else { return }
            self.recordingDuration = Date.now.timeIntervalSince(start)
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    // MARK: - Camera Switching & Flash & Aspect Ratio

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self,
                  self.internalIsConfigured,
                  !self.movieOutput.isRecording,
                  let currentInput = self.videoInput else {
                return
            }

            let nextPosition: AVCaptureDevice.Position =
                currentInput.device.position == .back ? .front : .back

            guard let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: nextPosition
            ) else {
                self.publishError(CameraServiceError.cameraUnavailable)
                return
            }

            do {
                let newInput = try AVCaptureDeviceInput(device: device)

                self.session.beginConfiguration()
                if self.session.canAddInput(newInput) {
                    self.session.removeInput(currentInput)
                    self.session.addInput(newInput)
                    self.videoInput = newInput
                }
                self.session.commitConfiguration()

                DispatchQueue.main.async {
                    self.isUsingFrontCamera = nextPosition == .front
                    self.isFlashAvailable = device.hasFlash
                    if !device.hasFlash {
                        self.flashMode = .off
                    }
                }
            } catch {
                self.publishError(error)
            }
        }
    }

    func cycleFlashMode() {
        guard isFlashAvailable else { return }
        switch flashMode {
        case .auto:
            flashMode = .on
        case .on:
            flashMode = .off
        case .off:
            flashMode = .auto
        }
    }

    func setFlashMode(_ mode: CameraFlashMode) {
        guard isFlashAvailable else { return }
        flashMode = mode
    }

    func cycleAspectRatio() {
        switch aspectRatio {
        case .ratio4_3:
            aspectRatio = .ratio16_9
        case .ratio16_9:
            aspectRatio = .ratio1_1
        case .ratio1_1:
            aspectRatio = .ratio4_3
        }
    }

    // MARK: - Save Media

    func savePhoto(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        saveToPhotoLibrary(changes: {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }, completion: completion)
    }

    func saveVideo(url: URL, completion: @escaping (Bool) -> Void) {
        saveToPhotoLibrary(changes: {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }, completion: completion)
    }

    private func saveToPhotoLibrary(changes: @escaping () -> Void, completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        let performSave: () -> Void = { [weak self] in
            PHPhotoLibrary.shared().performChanges {
                changes()
            } completionHandler: { [weak self] success, error in
                DispatchQueue.main.async {
                    if !success {
                        self?.errorMessage = error?.localizedDescription ?? "Unable to save media to Photos."
                    }
                    completion(success)
                }
            }
        }

        if status == .authorized || status == .limited {
            performSave()
        } else if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] newStatus in
                if newStatus == .authorized || newStatus == .limited {
                    performSave()
                } else {
                    DispatchQueue.main.async {
                        self?.publishError(CameraServiceError.permissionDenied)
                        completion(false)
                    }
                }
            }
        } else {
            publishError(CameraServiceError.permissionDenied)
            completion(false)
        }
    }

    // MARK: - Error Handling

    private func publishError(_ error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Photo Delegate

extension CameraService: AVCapturePhotoCaptureDelegate {

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            publishError(error)
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let rawImage = UIImage(data: data) else {
            publishError(CameraServiceError.photoDataUnavailable)
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let result = OverlayRenderer.processCapturedPhoto(
                image: rawImage,
                aspectRatio: self.aspectRatio,
                currentDBFS: self.currentDBFS,
                currentAcousticDB: self.currentAcousticDB,
                averageDBFS: self.averageDBFS,
                averageAcousticDB: self.averageAcousticDB,
                minimumDBFS: self.minimumDBFS,
                minimumAcousticDB: self.minimumAcousticDB,
                maximumDBFS: self.maximumDBFS,
                maximumAcousticDB: self.maximumAcousticDB,
                peakDBFS: self.peakDBFS,
                peakAcousticDB: self.peakAcousticDB,
                durationFormatted: self.recordingDurationFormatted,
                locationName: self.locationService.locationName,
                filter: self.selectedFilter,
                settings: self.overlaySettings,
                timestamp: Date()
            )

            self.capturedAnnotatedImage = result.annotated
            self.capturedRawImage = result.raw
        }
    }
}

// MARK: - Video Delegate & Overlay Export

extension CameraService: AVCaptureFileOutputRecordingDelegate {

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isRecording = false
            self.stopRecordingTimer()

            if let error {
                self.publishError(error)
                return
            }

            let exportOutputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("SoundMeter-export-\(UUID().uuidString).mov")

            self.isExportingVideo = true
            self.exportProgress = 0.0

            let snapshots = self.recordedSnapshots
            let filter = self.selectedFilter
            let settings = self.overlaySettings
            let startDate = self.recordingStartDate ?? Date()
            let locName = self.locationService.locationName

            VideoOverlayExporter.exportVideo(
                inputURL: outputFileURL,
                outputURL: exportOutputURL,
                snapshots: snapshots,
                filter: filter,
                overlaySettings: settings,
                recordingStartDate: startDate,
                locationName: locName,
                progress: { [weak self] prog in
                    DispatchQueue.main.async {
                        self?.exportProgress = prog
                    }
                },
                completion: { [weak self] result in
                    guard let self else { return }
                    DispatchQueue.main.async {
                        self.isExportingVideo = false
                        switch result {
                        case .success(let finalURL):
                            self.savedVideoURL = finalURL
                        case .failure(let exportErr):
                            self.errorMessage = exportErr.localizedDescription
                        }
                    }
                }
            )
        }
    }
}

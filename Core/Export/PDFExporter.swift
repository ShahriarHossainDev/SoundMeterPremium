import UIKit
import Foundation

/// Generates formatted, publication-quality acoustic measurement PDF reports
/// conforming to standard documentation layouts with embedded vector trend charts.
enum PDFExporter {

    /// Standard Letter page dimensions in points (8.5 x 11 inches at 72 dpi)
    private static let pageWidth: CGFloat = 612.0
    private static let pageHeight: CGFloat = 792.0
    private static let margin: CGFloat = 36.0
    private static var contentWidth: CGFloat { pageWidth - (margin * 2) }

    // Brand Palette for PDF Documents (Print-Friendly)
    private static let brandDark = UIColor(red: 0.08, green: 0.11, blue: 0.15, alpha: 1.0) // #141C26
    private static let brandMuted = UIColor(red: 0.40, green: 0.45, blue: 0.52, alpha: 1.0) // #667385
    private static let brandLightGray = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1.0) // #F5F7FA
    private static let brandBorder = UIColor(red: 0.88, green: 0.90, blue: 0.93, alpha: 1.0) // #E0E6EE
    private static let brandTeal = UIColor(red: 0.08, green: 0.65, blue: 0.57, alpha: 1.0) // #14A691
    private static let brandBlue = UIColor(red: 0.20, green: 0.45, blue: 0.90, alpha: 1.0) // #3373E6
    private static let brandOrange = UIColor(red: 0.92, green: 0.42, blue: 0.15, alpha: 1.0) // #EA6B26

    /// Exports a session as a formatted PDF file and returns its temporary URL.
    static func export(session: MeasurementSession) throws -> URL {
        let safeName = session.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        let filename = "Report_\(safeName)_\(session.id.uuidString.prefix(8)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        let data = generatePDFData(for: session)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Generates raw PDF Data for the given measurement session.
    static func generatePDFData(for session: MeasurementSession) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let format = UIGraphicsPDFRendererFormat()
        let metadata: [String: Any] = [
            kCGPDFContextTitle as String: "SoundMeter Report - \(session.title)",
            kCGPDFContextAuthor as String: "SoundMeter iOS",
            kCGPDFContextCreator as String: "SoundMeter Pro PDF Report Generator"
        ]
        format.documentInfo = metadata

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        return renderer.pdfData { context in
            context.beginPage()
            guard let cgContext = UIGraphicsGetCurrentContext() else { return }

            // 1. Header Banner & Title
            var currentY: CGFloat = margin
            currentY = drawHeader(in: cgContext, session: session, topY: currentY)

            // 2. Summary KPI Cards (Average, Peak, Minimum, Dynamic Range)
            currentY = drawMetricCards(in: cgContext, session: session, topY: currentY)

            // 3. Embedded Time-Series Line Chart
            currentY = drawChart(in: cgContext, session: session, topY: currentY)

            // 4. Detailed Statistical Table (Percentiles L10, L50, L90, Calibrations)
            currentY = drawStatisticsTable(in: cgContext, session: session, topY: currentY)

            // 5. Notes & Field Observations
            currentY = drawNotesSection(in: cgContext, session: session, topY: currentY)

            // 6. Regulatory Disclaimer & Page Footer
            drawFooter(in: cgContext, bottomY: pageHeight - margin)
        }
    }

    // MARK: - Section Renderers

    private static func drawHeader(in ctx: CGContext, session: MeasurementSession, topY: CGFloat) -> CGFloat {
        var y = topY

        // Top Brand Bar: Badge + Subtitle
        let badgeRect = CGRect(x: margin, y: y, width: 110, height: 18)
        let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: 4)
        brandDark.setFill()
        badgePath.fill()

        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8.5, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        ("SOUNDMETER PRO" as NSString).draw(at: CGPoint(x: margin + 8, y: y + 3.5), withAttributes: badgeAttrs)

        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8.5, weight: .semibold),
            .foregroundColor: brandMuted
        ]
        ("ACOUSTIC MEASUREMENT & SOUND LEVEL REPORT" as NSString).draw(
            at: CGPoint(x: margin + 118, y: y + 3.5),
            withAttributes: subtitleAttrs
        )

        // Date right-aligned
        let dateString = DateFormatter.localizedString(from: session.startedAt, dateStyle: .medium, timeStyle: .short)
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8.5, weight: .regular),
            .foregroundColor: brandMuted
        ]
        let dateSize = (dateString as NSString).size(withAttributes: dateAttrs)
        (dateString as NSString).draw(at: CGPoint(x: pageWidth - margin - dateSize.width, y: y + 3.5), withAttributes: dateAttrs)

        y += 24

        // Top Accent Rule
        let rulePath = UIBezierPath()
        rulePath.move(to: CGPoint(x: margin, y: y))
        rulePath.addLine(to: CGPoint(x: pageWidth - margin, y: y))
        rulePath.lineWidth = 1.5
        brandTeal.setStroke()
        rulePath.stroke()

        y += 12

        // Session Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: brandDark
        ]
        (session.title as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
        y += 26

        // Session Metadata line: Started - Ended | Duration | Weighting
        let durationFormatted = formatDuration(session.duration)
        let weightingInfo = FrequencyWeighting(rawValue: session.weighting)?.displayName ?? session.weighting
        let metaText = "Measured on \(dateString)  •  Duration: \(durationFormatted)  •  Filter: \(weightingInfo)"
        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: brandMuted
        ]
        (metaText as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: metaAttrs)

        y += 18
        return y
    }

    private static func drawMetricCards(in ctx: CGContext, session: MeasurementSession, topY: CGFloat) -> CGFloat {
        let cardHeight: CGFloat = 68.0
        let cardSpacing: CGFloat = 10.0
        let cardCount: CGFloat = 4.0
        let cardWidth = (contentWidth - ((cardCount - 1) * cardSpacing)) / cardCount

        let unitSymbol = FrequencyWeighting(rawValue: session.weighting)?.unitSymbol ?? "dBFS"
        let dynamicRange = max(0, session.maximumDBFS - session.minimumDBFS)

        let metrics: [(title: String, value: Double, unit: String, highlight: UIColor)] = [
            ("AVERAGE (Leq)", session.averageDBFS, unitSymbol, brandTeal),
            ("MAXIMUM PEAK", session.maximumDBFS, unitSymbol, brandOrange),
            ("MINIMUM LEVEL", session.minimumDBFS, unitSymbol, brandBlue),
            ("DYNAMIC RANGE", dynamicRange, "dB", brandMuted)
        ]

        for (i, m) in metrics.enumerated() {
            let cardX = margin + CGFloat(i) * (cardWidth + cardSpacing)
            let cardRect = CGRect(x: cardX, y: topY, width: cardWidth, height: cardHeight)

            // Background & Border
            let path = UIBezierPath(roundedRect: cardRect, cornerRadius: 8)
            brandLightGray.setFill()
            path.fill()
            brandBorder.setStroke()
            path.lineWidth = 1.0
            path.stroke()

            // Accent strip at top
            let stripRect = CGRect(x: cardX + 8, y: topY + 6, width: 22, height: 3)
            let stripPath = UIBezierPath(roundedRect: stripRect, cornerRadius: 1.5)
            m.highlight.setFill()
            stripPath.fill()

            // Title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8.0, weight: .bold),
                .foregroundColor: brandMuted
            ]
            (m.title as NSString).draw(at: CGPoint(x: cardX + 8, y: topY + 14), withAttributes: titleAttrs)

            // Value
            let valString = String(format: "%.1f", m.value)
            let valAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 18.0, weight: .bold),
                .foregroundColor: brandDark
            ]
            (valString as NSString).draw(at: CGPoint(x: cardX + 8, y: topY + 28), withAttributes: valAttrs)

            // Unit
            let unitAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8.5, weight: .semibold),
                .foregroundColor: m.highlight
            ]
            (m.unit as NSString).draw(at: CGPoint(x: cardX + 8, y: topY + 50), withAttributes: unitAttrs)
        }

        return topY + cardHeight + 14.0
    }

    private static func drawChart(in ctx: CGContext, session: MeasurementSession, topY: CGFloat) -> CGFloat {
        let chartContainerHeight: CGFloat = 220.0
        let containerRect = CGRect(x: margin, y: topY, width: contentWidth, height: chartContainerHeight)

        // Container card background
        let containerPath = UIBezierPath(roundedRect: containerRect, cornerRadius: 10)
        brandLightGray.setFill()
        containerPath.fill()
        brandBorder.setStroke()
        containerPath.lineWidth = 1.0
        containerPath.stroke()

        // Section Title & Legend
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10.0, weight: .bold),
            .foregroundColor: brandDark
        ]
        ("TIME-SERIES ACOUSTIC PROFILE" as NSString).draw(at: CGPoint(x: margin + 12, y: topY + 10), withAttributes: headerAttrs)

        // Legend elements on top right
        let legendY = topY + 11
        let legendRight = containerRect.maxX - 12

        let unitSymbol = FrequencyWeighting(rawValue: session.weighting)?.unitSymbol ?? "dBFS"
        let legendText = "— Measured Level (\(unitSymbol))    --- Leq Average"
        let legendAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8.0, weight: .medium),
            .foregroundColor: brandMuted
        ]
        let legSize = (legendText as NSString).size(withAttributes: legendAttrs)
        (legendText as NSString).draw(at: CGPoint(x: legendRight - legSize.width, y: legendY), withAttributes: legendAttrs)

        // Define Inner Plot Area
        let plotLeft: CGFloat = margin + 48.0
        let plotRight: CGFloat = containerRect.maxX - 16.0
        let plotTop: CGFloat = topY + 32.0
        let plotBottom: CGFloat = containerRect.maxY - 28.0
        let plotWidth = plotRight - plotLeft
        let plotHeight = plotBottom - plotTop
        let plotRect = CGRect(x: plotLeft, y: plotTop, width: plotWidth, height: plotHeight)

        // White background for inner plot
        let plotBgPath = UIBezierPath(rect: plotRect)
        UIColor.white.setFill()
        plotBgPath.fill()
        brandBorder.setStroke()
        plotBgPath.lineWidth = 1.0
        plotBgPath.stroke()

        // Compute Dynamic or Standard dBFS Range
        let samples = session.samples.sorted(by: { $0.elapsedSeconds < $1.elapsedSeconds })
        var minVal = -100.0
        var maxVal = 0.0

        if !samples.isEmpty {
            let actualMin = samples.map(\.levelDBFS).min() ?? -100.0
            let actualMax = samples.map(\.levelDBFS).max() ?? 0.0
            minVal = max(-120.0, floor((actualMin - 5.0) / 10.0) * 10.0)
            maxVal = min(20.0, ceil((actualMax + 5.0) / 10.0) * 10.0)
            if maxVal - minVal < 30.0 {
                minVal = maxVal - 30.0
            }
        }

        // Draw Horizontal Grid Lines & dBFS Labels
        let gridStep: Double = (maxVal - minVal) <= 40 ? 10.0 : 20.0
        var gridVal = ceil(minVal / gridStep) * gridStep
        let gridAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 7.5, weight: .regular),
            .foregroundColor: brandMuted
        ]

        while gridVal <= maxVal {
            let normY = CGFloat((gridVal - minVal) / (maxVal - minVal))
            let yPos = plotBottom - (normY * plotHeight)

            if yPos >= plotTop && yPos <= plotBottom {
                // Dashed grid line
                ctx.saveGState()
                ctx.setLineDash(phase: 0, lengths: [3, 3])
                ctx.setStrokeColor(brandBorder.cgColor)
                ctx.setLineWidth(0.75)
                ctx.move(to: CGPoint(x: plotLeft, y: yPos))
                ctx.addLine(to: CGPoint(x: plotRight, y: yPos))
                ctx.strokePath()
                ctx.restoreGState()

                // Y-axis label
                let labelText = String(format: "%.0f dB", gridVal)
                let labelSize = (labelText as NSString).size(withAttributes: gridAttrs)
                (labelText as NSString).draw(
                    at: CGPoint(x: plotLeft - labelSize.width - 5, y: yPos - (labelSize.height / 2)),
                    withAttributes: gridAttrs
                )
            }
            gridVal += gridStep
        }

        // Draw Vertical Grid Lines & Time Markers
        let totalTime = max(session.duration, samples.last?.elapsedSeconds ?? 1.0)
        let timeSteps = 4
        for step in 0...timeSteps {
            let fraction = CGFloat(step) / CGFloat(timeSteps)
            let xPos = plotLeft + (fraction * plotWidth)
            let stepSeconds = Double(fraction) * totalTime

            // Vertical tick / grid line
            ctx.saveGState()
            ctx.setLineDash(phase: 0, lengths: [2, 3])
            ctx.setStrokeColor(brandBorder.withAlphaComponent(0.6).cgColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: xPos, y: plotTop))
            ctx.addLine(to: CGPoint(x: xPos, y: plotBottom))
            ctx.strokePath()
            ctx.restoreGState()

            // Time label below X-axis
            let timeString = formatTimeAxis(stepSeconds)
            let timeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 7.5, weight: .regular),
                .foregroundColor: brandMuted
            ]
            let timeSize = (timeString as NSString).size(withAttributes: timeAttrs)
            let labelX = min(max(xPos - (timeSize.width / 2), plotLeft), plotRight - timeSize.width)
            (timeString as NSString).draw(at: CGPoint(x: labelX, y: plotBottom + 4), withAttributes: timeAttrs)
        }

        // Plot Samples & Shaded Area
        if samples.count > 1 {
            let linePath = UIBezierPath()
            let areaPath = UIBezierPath()

            for (idx, sample) in samples.enumerated() {
                let fracX = CGFloat(sample.elapsedSeconds / totalTime)
                let clampedFracX = min(max(fracX, 0.0), 1.0)
                let xCoord = plotLeft + (clampedFracX * plotWidth)

                let normLevel = CGFloat((sample.levelDBFS - minVal) / (maxVal - minVal))
                let clampedNormLevel = min(max(normLevel, 0.0), 1.0)
                let yCoord = plotBottom - (clampedNormLevel * plotHeight)

                let pt = CGPoint(x: xCoord, y: yCoord)
                if idx == 0 {
                    linePath.move(to: pt)
                    areaPath.move(to: CGPoint(x: xCoord, y: plotBottom))
                    areaPath.addLine(to: pt)
                } else {
                    linePath.addLine(to: pt)
                    areaPath.addLine(to: pt)
                }

                if idx == samples.count - 1 {
                    areaPath.addLine(to: CGPoint(x: xCoord, y: plotBottom))
                    areaPath.close()
                }
            }

            // Fill shaded gradient under curve
            ctx.saveGState()
            areaPath.addClip()
            let colors = [brandTeal.withAlphaComponent(0.25).cgColor, brandTeal.withAlphaComponent(0.02).cgColor] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
                ctx.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: plotLeft, y: plotTop),
                    end: CGPoint(x: plotLeft, y: plotBottom),
                    options: []
                )
            }
            ctx.restoreGState()

            // Stroke line path
            linePath.lineWidth = 1.75
            linePath.lineJoinStyle = .round
            linePath.lineCapStyle = .round
            brandTeal.setStroke()
            linePath.stroke()

            // Average Leq Reference Line across chart
            if session.averageDBFS >= minVal && session.averageDBFS <= maxVal {
                let avgNorm = CGFloat((session.averageDBFS - minVal) / (maxVal - minVal))
                let avgYPos = plotBottom - (avgNorm * plotHeight)

                ctx.saveGState()
                ctx.setLineDash(phase: 0, lengths: [4, 3])
                ctx.setStrokeColor(brandBlue.cgColor)
                ctx.setLineWidth(1.2)
                ctx.move(to: CGPoint(x: plotLeft, y: avgYPos))
                ctx.addLine(to: CGPoint(x: plotRight, y: avgYPos))
                ctx.strokePath()
                ctx.restoreGState()
            }
        } else {
            // Placeholder when no samples exist
            let emptyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10.0, weight: .medium),
                .foregroundColor: brandMuted
            ]
            let emptyMsg = "No continuous graph samples recorded for this session."
            let emptySize = (emptyMsg as NSString).size(withAttributes: emptyAttrs)
            (emptyMsg as NSString).draw(
                at: CGPoint(x: plotLeft + (plotWidth - emptySize.width) / 2, y: plotTop + (plotHeight - emptySize.height) / 2),
                withAttributes: emptyAttrs
            )
        }

        return topY + chartContainerHeight + 14.0
    }

    private static func drawStatisticsTable(in ctx: CGContext, session: MeasurementSession, topY: CGFloat) -> CGFloat {
        let tableHeight: CGFloat = 82.0
        let tableRect = CGRect(x: margin, y: topY, width: contentWidth, height: tableHeight)

        let tablePath = UIBezierPath(roundedRect: tableRect, cornerRadius: 8)
        brandLightGray.setFill()
        tablePath.fill()
        brandBorder.setStroke()
        tablePath.lineWidth = 1.0
        tablePath.stroke()

        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9.0, weight: .bold),
            .foregroundColor: brandDark
        ]
        ("STATISTICAL PERCENTILES & EXPOSURE SUMMARY" as NSString).draw(
            at: CGPoint(x: margin + 12, y: topY + 8),
            withAttributes: titleAttrs
        )

        let samples = session.samples.map(\.levelDBFS).sorted(by: >) // loud to quiet
        let unitSymbol = FrequencyWeighting(rawValue: session.weighting)?.unitSymbol ?? "dBFS"

        // Compute L10, L50, L90 percentiles
        let l10Val: String
        let l50Val: String
        let l90Val: String
        if !samples.isEmpty {
            let i10 = min(max(Int(Double(samples.count) * 0.10), 0), samples.count - 1)
            let i50 = min(max(Int(Double(samples.count) * 0.50), 0), samples.count - 1)
            let i90 = min(max(Int(Double(samples.count) * 0.90), 0), samples.count - 1)
            l10Val = String(format: "%.1f %@", samples[i10], unitSymbol)
            l50Val = String(format: "%.1f %@", samples[i50], unitSymbol)
            l90Val = String(format: "%.1f %@", samples[i90], unitSymbol)
        } else {
            l10Val = "N/A"
            l50Val = "N/A"
            l90Val = "N/A"
        }

        let colWidth = (contentWidth - 24) / 4
        let row1Y = topY + 28
        let row2Y = topY + 52

        let items: [(label: String, val: String, x: CGFloat, y: CGFloat)] = [
            ("L10 (Peak Exposure)", l10Val, margin + 12, row1Y),
            ("L50 (Median Level)", l50Val, margin + 12 + colWidth, row1Y),
            ("L90 (Ambient Floor)", l90Val, margin + 12 + (colWidth * 2), row1Y),
            ("Total Samples", "\(session.samples.count)", margin + 12 + (colWidth * 3), row1Y),
            ("Weighting Curve", session.weighting, margin + 12, row2Y),
            ("Calibration Offset", String(format: "%+.1f dB", session.calibrationOffsetDB), margin + 12 + colWidth, row2Y),
            ("Peak-to-Average", String(format: "%.1f dB", max(0, session.maximumDBFS - session.averageDBFS)), margin + 12 + (colWidth * 2), row2Y),
            ("Session Status", "Complete", margin + 12 + (colWidth * 3), row2Y)
        ]

        let lblAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7.5, weight: .regular),
            .foregroundColor: brandMuted
        ]
        let valAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 9.5, weight: .semibold),
            .foregroundColor: brandDark
        ]

        for item in items {
            (item.label as NSString).draw(at: CGPoint(x: item.x, y: item.y), withAttributes: lblAttrs)
            (item.val as NSString).draw(at: CGPoint(x: item.x, y: item.y + 11), withAttributes: valAttrs)
        }

        return topY + tableHeight + 12.0
    }

    private static func drawNotesSection(in ctx: CGContext, session: MeasurementSession, topY: CGFloat) -> CGFloat {
        let notesHeight: CGFloat = 58.0
        let notesRect = CGRect(x: margin, y: topY, width: contentWidth, height: notesHeight)

        let path = UIBezierPath(roundedRect: notesRect, cornerRadius: 8)
        brandLightGray.setFill()
        path.fill()
        brandBorder.setStroke()
        path.lineWidth = 1.0
        path.stroke()

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8.5, weight: .bold),
            .foregroundColor: brandDark
        ]
        ("FIELD NOTES & OBSERVATIONS" as NSString).draw(at: CGPoint(x: margin + 10, y: topY + 8), withAttributes: titleAttrs)

        let notesText = session.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No additional field notes were logged during this recording."
            : session.notes

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8.5, weight: .regular),
            .foregroundColor: session.notes.isEmpty ? brandMuted : brandDark
        ]
        let textRect = CGRect(x: margin + 10, y: topY + 22, width: contentWidth - 20, height: notesHeight - 26)
        (notesText as NSString).draw(in: textRect, withAttributes: textAttrs)

        return topY + notesHeight + 14.0
    }

    private static func drawFooter(in ctx: CGContext, bottomY: CGFloat) -> Void {
        let footerY = bottomY - 32.0

        // Subtle rule above footer
        let rulePath = UIBezierPath()
        rulePath.move(to: CGPoint(x: margin, y: footerY))
        rulePath.addLine(to: CGPoint(x: pageWidth - margin, y: footerY))
        rulePath.lineWidth = 0.5
        brandBorder.setStroke()
        rulePath.stroke()

        // Compliance & Legal Disclaimer
        let disclaimer = "NOTICE: Digital measurements represent decibels relative to full scale (dBFS) filtered according to IEC 61672-1 standards. Values are comparative indicators and do not certify absolute SPL compliance without calibrated hardware."
        let disAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 6.5, weight: .regular),
            .foregroundColor: brandMuted
        ]
        let disRect = CGRect(x: margin, y: footerY + 5, width: contentWidth - 80, height: 24)
        (disclaimer as NSString).draw(in: disRect, withAttributes: disAttrs)

        // Page Number right-aligned
        let pageStr = "Page 1 of 1"
        let pageAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 8.0, weight: .semibold),
            .foregroundColor: brandMuted
        ]
        let pageSz = (pageStr as NSString).size(withAttributes: pageAttrs)
        (pageStr as NSString).draw(at: CGPoint(x: pageWidth - margin - pageSz.width, y: footerY + 10), withAttributes: pageAttrs)
    }

    // MARK: - Helpers

    private static func formatDuration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        let minutes = s / 60
        let remSec = s % 60
        return String(format: "%02d:%02d", minutes, remSec)
    }

    private static func formatTimeAxis(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

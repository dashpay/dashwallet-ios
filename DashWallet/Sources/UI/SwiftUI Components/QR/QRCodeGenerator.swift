//
//  QRCodeGenerator.swift
//  DashWallet
//

import CoreImage.CIFilterBuiltins
import UIKit

enum QRCodeGenerator {
    /// QR error-correction level. Higher levels survive more damage/occlusion
    /// at the cost of denser modules. Anything that cuts a hole for a center
    /// logo must use `.high` (30% recovery budget).
    enum CorrectionLevel: String {
        case low = "L"
        case medium = "M"
        case quartile = "Q"
        case high = "H"
    }

    static func image(for string: String,
                      size: CGFloat = 280,
                      correctionLevel: CorrectionLevel = .high) -> UIImage? {
        image(for: Data(string.utf8), size: size, correctionLevel: correctionLevel)
    }

    static func image(for data: Data,
                      size: CGFloat = 280,
                      correctionLevel: CorrectionLevel = .high) -> UIImage? {
        guard let output = qrOutputImage(for: data, correctionLevel: correctionLevel) else { return nil }
        let scale = size / output.extent.width
        return rendered(output.transformed(by: CGAffineTransform(scaleX: scale, y: scale)))
    }

    /// QR with colored modules on a transparent background, at module scale
    /// (1 pixel per module) — display or composite with nearest-neighbor
    /// scaling to keep edges crisp. The dynamic-color resolution happens
    /// here, once, against the current trait collection (same behavior as
    /// the legacy `dw_imageWithQRCodeData:color:` this replaces).
    static func image(for data: Data,
                      correctionLevel: CorrectionLevel = .quartile,
                      foregroundColor: UIColor) -> UIImage? {
        guard let qrImage = qrOutputImage(for: data, correctionLevel: correctionLevel),
              let invertFilter = CIFilter(name: "CIColorInvert"),
              let maskFilter = CIFilter(name: "CIMaskToAlpha"),
              let colorFilter = CIFilter(name: "CIFalseColor") else { return nil }

        // dark modules → white → alpha mask → invert back → tint
        invertFilter.setValue(qrImage, forKey: "inputImage")
        maskFilter.setValue(invertFilter.outputImage, forKey: "inputImage")
        invertFilter.setValue(maskFilter.outputImage, forKey: "inputImage")
        colorFilter.setValue(invertFilter.outputImage, forKey: "inputImage")
        colorFilter.setValue(CIColor(color: foregroundColor), forKey: "inputColor0")

        guard let output = colorFilter.outputImage else { return nil }
        return rendered(output)
    }

    /// One-pass port of the legacy receive-QR pipeline
    /// (`dw_resize` → `dw_imageByCuttingHoleInCenter` → `dw_imageByMerging`):
    /// nearest-neighbor upscale of a module-scale QR, a circular hole
    /// cleared in the center, and an overlay (logo or username disc) drawn
    /// over it. The source QR must be encoded at a correction level whose
    /// recovery budget covers the hole.
    static func composited(rawQRImage: UIImage,
                           targetSize: CGSize,
                           holeSize: CGSize,
                           overlay: UIImage?,
                           overlaySize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { rendererContext in
            let context = rendererContext.cgContext
            let rect = CGRect(origin: .zero, size: targetSize)

            // Nearest-neighbor for the QR modules only — the overlay below
            // is a smooth-scaled logo/disc (legacy pipeline resized it with
            // kCGInterpolationHigh, and the modules with None).
            context.saveGState()
            context.interpolationQuality = .none
            rawQRImage.draw(in: rect)
            context.restoreGState()
            context.interpolationQuality = .high

            if holeSize.width > 0 {
                let radius = ceil(holeSize.width / 2)
                let center = CGPoint(x: targetSize.width / 2, y: targetSize.height / 2)
                context.saveGState()
                context.addEllipse(in: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2))
                context.clip()
                context.clear(rect)
                context.restoreGState()
            }

            if let overlay {
                overlay.draw(in: CGRect(
                    x: (targetSize.width - overlaySize.width) / 2,
                    y: (targetSize.height - overlaySize.height) / 2,
                    width: overlaySize.width,
                    height: overlaySize.height))
            }
        }
    }

    /// 2D barcode rendering for the CIFilter-backed formats. Returns nil for
    /// formats CoreImage cannot generate (EAN/UPC/ITF/…) — callers decide
    /// their own fallback. Result is at generator scale with per-format
    /// multipliers tuned for on-screen legibility; display with
    /// nearest-neighbor interpolation.
    static func barcodeImage(value: String, format: BarcodeFormat) -> UIImage? {
        guard !value.isEmpty,
              let filterName = format.ciFilterName,
              let filter = CIFilter(name: filterName) else { return nil }

        filter.setValue(Data(value.utf8), forKey: "inputMessage")

        let transform: CGAffineTransform
        switch format {
        case .qrCode:
            filter.setValue(CorrectionLevel.medium.rawValue, forKey: "inputCorrectionLevel")
            transform = CGAffineTransform(scaleX: 6, y: 6)
        case .pdf417:
            transform = CGAffineTransform(scaleX: 3, y: 3)
        case .aztec:
            transform = CGAffineTransform(scaleX: 6, y: 6)
        case .dataMatrix:
            transform = CGAffineTransform(scaleX: 8, y: 8)
        default:
            transform = CGAffineTransform(scaleX: 3, y: 5)
        }

        guard let output = filter.outputImage else { return nil }
        return rendered(output.transformed(by: transform))
    }

    // MARK: - CoreImage plumbing

    /// The CIQRCodeGenerator output for `data`, one pixel per module.
    private static func qrOutputImage(for data: Data, correctionLevel: CorrectionLevel) -> CIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(correctionLevel.rawValue, forKey: "inputCorrectionLevel")
        return filter.outputImage
    }

    private static func rendered(_ ciImage: CIImage) -> UIImage? {
        guard let cgImage = renderedCGImage(ciImage) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func renderedCGImage(_ ciImage: CIImage) -> CGImage? {
        CIContext().createCGImage(ciImage, from: ciImage.extent)
    }

    // MARK: - Dash-branded rendering

    /// Dash-branded QR code: round modules under a Dash-blue gradient,
    /// rounded finder eyes, and the Dash logo on a white disc in the
    /// center. Encoded at error-correction level H, so the ~9% of
    /// modules the logo disc hides stay well inside the 30% recovery
    /// budget. Modules are drawn in Dash blue on a transparent
    /// background — present on a white/light surface for contrast.
    static func dashStyledImage(for string: String, size: CGFloat) -> UIImage? {
        guard let matrix = moduleMatrix(for: string), matrix.count >= 21 else { return nil }
        let moduleCount = matrix.count
        let module = size / CGFloat(moduleCount)
        let imageCenter = CGPoint(x: size / 2, y: size / 2)
        // Modules whose center falls inside this radius are skipped to
        // clear a landing zone for the logo disc (π·0.16² ≈ 8% of area).
        let clearRadius = size * 0.16

        // (col, row) of the three 7×7 finder patterns; they are drawn
        // as custom rounded eyes instead of dots.
        let finderOrigins = [(0, 0), (moduleCount - 7, 0), (0, moduleCount - 7)]
        func isInFinder(col: Int, row: Int) -> Bool {
            finderOrigins.contains { col >= $0.0 && col < $0.0 + 7 && row >= $0.1 && row < $0.1 + 7 }
        }

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        return renderer.image { rendererContext in
            let context = rendererContext.cgContext
            let path = CGMutablePath()

            // Data modules as circles.
            let dotDiameter = module * 0.86
            for row in 0..<moduleCount {
                for col in 0..<moduleCount where matrix[row][col] {
                    if isInFinder(col: col, row: row) { continue }
                    let dotCenter = CGPoint(
                        x: (CGFloat(col) + 0.5) * module,
                        y: (CGFloat(row) + 0.5) * module)
                    if hypot(dotCenter.x - imageCenter.x, dotCenter.y - imageCenter.y) < clearRadius {
                        continue
                    }
                    path.addEllipse(in: CGRect(
                        x: dotCenter.x - dotDiameter / 2,
                        y: dotCenter.y - dotDiameter / 2,
                        width: dotDiameter,
                        height: dotDiameter))
                }
            }

            // Finder eyes: a rounded ring (7×7 outer, 5×5 hole via the
            // even-odd rule) plus a rounded 3×3 pupil.
            for origin in finderOrigins {
                let box = CGRect(
                    x: CGFloat(origin.0) * module,
                    y: CGFloat(origin.1) * module,
                    width: 7 * module,
                    height: 7 * module)
                path.addRoundedRect(in: box, cornerWidth: module * 2.4, cornerHeight: module * 2.4)
                path.addRoundedRect(
                    in: box.insetBy(dx: module, dy: module),
                    cornerWidth: module * 1.7, cornerHeight: module * 1.7)
                path.addRoundedRect(
                    in: box.insetBy(dx: 2 * module, dy: 2 * module),
                    cornerWidth: module * 1.1, cornerHeight: module * 1.1)
            }

            // One gradient across all modules. Both stops stay dark
            // enough against white for scanner binarization.
            context.saveGState()
            context.addPath(path)
            context.clip(using: .evenOdd)
            let dashBlue = UIColor(red: 0x00 / 255.0, green: 0x8D / 255.0, blue: 0xE4 / 255.0, alpha: 1)
            let deepBlue = UIColor(red: 0x01 / 255.0, green: 0x2C / 255.0, blue: 0x7A / 255.0, alpha: 1)
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [dashBlue.cgColor, deepBlue.cgColor] as CFArray,
                locations: [0, 1]) {
                context.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size, y: size),
                    options: [])
            }
            context.restoreGState()

            // Center: white backing disc, then the Dash logo disc with
            // a white ring of breathing room between it and the dots.
            let discRadius = size * 0.155
            UIColor.white.setFill()
            context.fillEllipse(in: CGRect(
                x: imageCenter.x - discRadius,
                y: imageCenter.y - discRadius,
                width: discRadius * 2,
                height: discRadius * 2))
            if let logo = UIImage(named: "dashCircleFilled") {
                let logoDiameter = size * 0.25
                logo.draw(in: CGRect(
                    x: imageCenter.x - logoDiameter / 2,
                    y: imageCenter.y - logoDiameter / 2,
                    width: logoDiameter,
                    height: logoDiameter))
            }
        }
    }

    /// Decode the CIQRCodeGenerator bitmap (1 pixel per module) into a
    /// square bool matrix, quiet zone stripped. `true` = dark module.
    /// Row 0 is the top of the symbol.
    private static func moduleMatrix(for string: String) -> [[Bool]]? {
        guard let output = qrOutputImage(for: Data(string.utf8), correctionLevel: .high),
              let cgImage = renderedCGImage(output) else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let bitmap = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        bitmap.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        func isDark(_ x: Int, _ y: Int) -> Bool {
            pixels[y * width + x] < 128
        }

        // The bounding box of dark pixels is the symbol; anything
        // outside is the generator's quiet border.
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where isDark(x, y) {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        let side = maxX - minX + 1
        guard side > 0, side == maxY - minY + 1 else { return nil }

        return (0..<side).map { row in
            (0..<side).map { col in
                isDark(minX + col, minY + row)
            }
        }
    }
}

// MARK: - Obj-C bridge

/// Obj-C face of `QRCodeGenerator` for the legacy receive stack
/// (`DWBaseReceiveModel`). New code should call `QRCodeGenerator` directly.
@objc(DWQRCodeFactory)
final class QRCodeFactory: NSObject {
    override private init() {}

    @objc static func compositedQRImage(rawQRImage: UIImage,
                                        targetSize: CGSize,
                                        holeSize: CGSize,
                                        overlay: UIImage?,
                                        overlaySize: CGSize) -> UIImage {
        QRCodeGenerator.composited(
            rawQRImage: rawQRImage,
            targetSize: targetSize,
            holeSize: holeSize,
            overlay: overlay,
            overlaySize: overlaySize)
    }

    /// The DashPay username disc drawn in the center of the receive QR:
    /// a username-colored circle with a Dash-blue rim and the initial
    /// letter. Port of the renderer block formerly inlined in
    /// `DWBaseReceiveModel qrCodeImageWithRawQRImage:hasAmount:`.
    @objc static func usernameOverlayImage(username: String,
                                           size: CGSize,
                                           hasAmount: Bool) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { rendererContext in
            let context = rendererContext.cgContext
            let rect = CGRect(origin: .zero, size: size)

            let backgroundColor = UIColor.dw_color(withUsername: username)
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            backgroundColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

            context.setFillColor(red: red, green: green, blue: blue, alpha: alpha)
            context.setStrokeColor(red: 62.0 / 255.0, green: 141.0 / 255.0, blue: 221.0 / 255.0, alpha: 1) // Dash-blue rim

            // Stroke at 2× width, clipped to the disc, so the visible rim
            // is exactly `strokeWidth` inside the circle's edge.
            let strokeWidth: CGFloat = hasAmount ? 4 : 5
            context.setLineWidth(strokeWidth * 2)

            let path = UIBezierPath(ovalIn: rect).cgPath
            context.addPath(path)
            context.clip()
            context.addPath(path)
            context.drawPath(using: .eoFillStroke)

            let font = UIFont.dw_regularFont(ofSize: hasAmount ? 20 : 30)
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.minimumLineHeight = rect.height / 2 + font.lineHeight / 2
            let initial = NSAttributedString(
                string: String(username.prefix(1)).uppercased(),
                attributes: [
                    .font: font,
                    .foregroundColor: UIColor.dw_lightTitle(),
                    .paragraphStyle: style,
                ])
            initial.draw(in: rect)
        }
    }
}

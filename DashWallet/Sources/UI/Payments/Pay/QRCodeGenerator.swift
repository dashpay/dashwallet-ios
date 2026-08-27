//
//  QRCodeGenerator.swift
//  DashWallet
//

import CoreImage.CIFilterBuiltins
import UIKit

enum QRCodeGenerator {
    static func image(for string: String, size: CGFloat = 280) -> UIImage? {
        let data = Data(string.utf8)
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let output = filter.outputImage else { return nil }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
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
        let data = Data(string.utf8)
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }

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

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
}

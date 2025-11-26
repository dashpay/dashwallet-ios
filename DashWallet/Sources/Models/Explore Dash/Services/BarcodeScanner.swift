//
//  Created by Claude Code
//  Copyright © 2025 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import UIKit
import Vision

/// Barcode format enumeration matching common barcode types
enum BarcodeFormat: String {
    case code128 = "CODE_128"
    case qrCode = "QR_CODE"
    case code39 = "CODE_39"
    case code93 = "CODE_93"
    case ean13 = "EAN_13"
    case ean8 = "EAN_8"
    case upca = "UPC_A"
    case upce = "UPC_E"
    case pdf417 = "PDF_417"
    case aztec = "AZTEC"
    case dataMatrix = "DATA_MATRIX"
    case itf = "ITF"
    case unknown = "UNKNOWN"

    /// Convert Vision framework symbology to BarcodeFormat
    static func from(symbology: VNBarcodeSymbology) -> BarcodeFormat {
        switch symbology {
        case .code128:
            return .code128
        case .qr:
            return .qrCode
        case .code39:
            return .code39
        case .code93:
            return .code93
        case .ean13:
            return .ean13
        case .ean8:
            return .ean8
        case .upce:
            return .upce
        case .pdf417:
            return .pdf417
        case .aztec:
            return .aztec
        case .dataMatrix:
            return .dataMatrix
        case .itf14:
            return .itf
        default:
            return .unknown
        }
    }

    /// Get CIFilter name for generating barcode images
    var ciFilterName: String? {
        switch self {
        case .code128:
            return "CICode128BarcodeGenerator"
        case .qrCode:
            return "CIQRCodeGenerator"
        case .pdf417:
            return "CIPDF417BarcodeGenerator"
        case .aztec:
            return "CIAztecCodeGenerator"
        case .dataMatrix:
            return "CIDataMatrixCodeGenerator"
        default:
            // Other formats don't have native CIFilter support
            return nil
        }
    }
}

/// Result from barcode scanning
struct BarcodeResult {
    let value: String
    let format: BarcodeFormat
}

/// Utility for downloading and scanning barcodes from URLs
class BarcodeScanner {

    /// Download barcode image from URL and scan it to extract value and format
    /// - Parameter url: The URL of the barcode image
    /// - Returns: BarcodeResult containing the value and format, or nil if scanning failed
    static func downloadAndScan(from url: String) async -> BarcodeResult? {
        // First try to extract barcode value from URL query parameters (faster and more reliable)
        if let extractedValue = extractBarcodeFromURL(url) {
            return BarcodeResult(value: extractedValue, format: .code128)
        }

        // Fallback: Download and scan the image
        guard let imageUrl = URL(string: url) else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: imageUrl)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            return await scanBarcode(from: data)
        } catch {
            return nil
        }
    }

    /// Extract barcode value from URL query parameters
    /// - Parameter url: The URL that may contain barcode data
    /// - Returns: Barcode value if found in URL parameters
    private static func extractBarcodeFromURL(_ url: String) -> String? {
        guard let urlComponents = URLComponents(string: url) else {
            return nil
        }

        // Check common parameter names for barcode data
        let parameterNames = ["text", "data", "code", "barcode"]
        for paramName in parameterNames {
            if let value = urlComponents.queryItems?.first(where: { $0.name == paramName })?.value {
                return value
            }
        }

        return nil
    }

    /// Scan barcode from image data
    /// - Parameter imageData: The image data to scan
    /// - Returns: BarcodeResult containing the value and format, or nil if scanning failed
    private static func scanBarcode(from imageData: Data) async -> BarcodeResult? {
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            return nil
        }

        return await scanBarcode(from: cgImage)
    }

    /// Scan barcode from CGImage using Vision framework
    /// - Parameter cgImage: The CGImage to scan
    /// - Returns: BarcodeResult containing the value and format, or nil if scanning failed
    private static func scanBarcode(from cgImage: CGImage) async -> BarcodeResult? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var resumed = false  // Prevent double-resumption

                let request = VNDetectBarcodesRequest { request, error in
                    guard !resumed else { return }
                    resumed = true

                    if let error = error {
                        continuation.resume(returning: nil)
                        return
                    }

                    guard let observations = request.results as? [VNBarcodeObservation],
                          let firstBarcode = observations.first,
                          let payloadString = firstBarcode.payloadStringValue else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let format = BarcodeFormat.from(symbology: firstBarcode.symbology)
                    let result = BarcodeResult(value: payloadString, format: format)

                    continuation.resume(returning: result)
                }

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                do {
                    try handler.perform([request])
                } catch {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

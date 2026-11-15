import XCTest
@testable import dashpay

final class BarcodeFormatTests: XCTestCase {
    func testCtxBarcodeTypesMapToTheirFormats() {
        XCTAssertEqual(BarcodeFormat.normalized("code39"), .code39)
        XCTAssertEqual(BarcodeFormat.normalized("code93"), .code93)
        XCTAssertEqual(BarcodeFormat.normalized("code128"), .code128)
        XCTAssertEqual(BarcodeFormat.normalized("pdf417"), .pdf417)
        XCTAssertEqual(BarcodeFormat.normalized("aztec"), .aztec)
        XCTAssertEqual(BarcodeFormat.normalized("qr"), .qrCode)
    }

    func testCaseAndSeparatorsAreNormalised() {
        XCTAssertEqual(BarcodeFormat.normalized(" Code-128 "), .code128)
        XCTAssertEqual(BarcodeFormat.normalized("qr_code"), .qrCode)
        XCTAssertEqual(BarcodeFormat.normalized("QrCode"), .qrCode)
        XCTAssertEqual(BarcodeFormat.normalized("data-matrix"), .dataMatrix)
        XCTAssertEqual(BarcodeFormat.normalized("DATAMATRIX"), .dataMatrix)
        XCTAssertEqual(BarcodeFormat.normalized("aztec_code"), .aztec)
    }

    func testRawValuesRoundTrip() {
        let formats: [BarcodeFormat] = [
            .code128, .qrCode, .code39, .code93, .ean13, .ean8,
            .upca, .upce, .pdf417, .aztec, .dataMatrix, .itf,
        ]
        for format in formats {
            XCTAssertEqual(BarcodeFormat.normalized(format.rawValue), format)
        }
    }

    func testMissingFormatKeepsTheCode128Default() {
        XCTAssertEqual(BarcodeFormat.normalized(nil), .code128)
        XCTAssertEqual(BarcodeFormat.normalized(""), .code128)
    }

    func testUnrecognisedFormatStaysUnknownAndDrawsNothing() {
        XCTAssertEqual(BarcodeFormat.normalized("maxicode"), .unknown)
        XCTAssertEqual(BarcodeFormat.normalized("UNKNOWN"), .unknown)
        XCTAssertNil(BarcodeFormat.unknown.generatorFilterName)
    }

    func testCode128StandsInOnlyForOneDimensionalFormats() {
        XCTAssertEqual(BarcodeFormat.code39.generatorFilterName, "CICode128BarcodeGenerator")
        XCTAssertEqual(BarcodeFormat.code93.generatorFilterName, "CICode128BarcodeGenerator")
        XCTAssertEqual(BarcodeFormat.qrCode.generatorFilterName, "CIQRCodeGenerator")
        XCTAssertEqual(BarcodeFormat.pdf417.generatorFilterName, "CIPDF417BarcodeGenerator")
        XCTAssertEqual(BarcodeFormat.aztec.generatorFilterName, "CIAztecCodeGenerator")
        XCTAssertNil(BarcodeFormat.dataMatrix.generatorFilterName)
    }
}

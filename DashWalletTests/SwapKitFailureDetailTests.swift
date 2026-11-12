//
//  SwapKitFailureDetailTests.swift
//  DashWalletTests
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

@testable import dashpay
import Moya
import XCTest

final class SwapKitFailureDetailTests: XCTestCase {
    private static let swapToURL = "https://api.swapkit.dev/swapTo?sellAsset=DASH.DASH"

    private func statusError(_ code: Int, _ body: Data, url: String = swapToURL) throws -> Error {
        let request = URLRequest(url: try XCTUnwrap(URL(string: url)))
        return HTTPClientError.statusCode(Response(statusCode: code, data: body, request: request))
    }

    func testAnHTMLRefusalShowsItsTitleAndThePathWithoutTheQuery() throws {
        let html = "<!DOCTYPE html>\n<html><head>\n<title>Attention Required! | Cloudflare</title>\n"
            + "</head><body>blocked</body></html>"
        let error = try statusError(403, Data(html.utf8))

        XCTAssertEqual(
            SwapKitFailureDetail.describe(error),
            "HTTP 403 /swapTo (\(html.utf8.count) bytes): Attention Required! | Cloudflare"
        )
    }

    func testATitleTagWithAttributesInAnyCaseIsRead() throws {
        let html = "<html><head><TITLE id=\"t\">Blocked</TITLE></head><body>x</body></html>"
        let detail = SwapKitFailureDetail.describe(try statusError(403, Data(html.utf8)))

        XCTAssertEqual(detail, "HTTP 403 /swapTo (\(html.utf8.count) bytes): Blocked")
    }

    func testAnEmptyTitleFallsBackToTheBody() throws {
        let html = "<title> </title><p>Access denied</p>"
        let detail = SwapKitFailureDetail.describe(try statusError(403, Data(html.utf8)))

        XCTAssertEqual(detail, "HTTP 403 /swapTo (\(html.utf8.count) bytes): <title> </title><p>Access denied</p>")
    }

    func testAJSONBodyIsShownOnOneLine() throws {
        let json = "{\"error\":\"apiKeyInvalid\",\n  \"message\":\"apiKeyInvalid\",\"data\":{}}"
        let error = try statusError(401, Data(json.utf8))
        let oneLine = "{\"error\":\"apiKeyInvalid\", \"message\":\"apiKeyInvalid\",\"data\":{}}"

        XCTAssertEqual(SwapKitFailureDetail.describe(error), "HTTP 401 /swapTo (\(json.utf8.count) bytes): \(oneLine)")
    }

    func testALongBodyIsCut() throws {
        let body = String(repeating: "a", count: 500)
        let error = try statusError(429, Data(body.utf8), url: "https://api.swapkit.dev/v3/quote")
        let detail = SwapKitFailureDetail.describe(error)

        XCTAssertEqual(detail, "HTTP 429 /v3/quote (500 bytes): " + String(repeating: "a", count: 200) + "…")
    }

    func testANonUTF8BodyIsNamedNotPrinted() throws {
        let detail = SwapKitFailureDetail.describe(try statusError(403, Data([0xFF, 0xFE, 0x00])))

        XCTAssertEqual(detail, "HTTP 403 /swapTo (3 bytes): <non-utf8 body>")
    }

    func testAnErrorWithoutAResponseUsesItsDescription() {
        let error = URLError(.notConnectedToInternet)

        XCTAssertEqual(SwapKitFailureDetail.describe(error), error.localizedDescription)
    }
}

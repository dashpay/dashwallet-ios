//
//  SwapKitFailureDetail.swift
//  DashWallet
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

import Foundation

/// One log line about a failed SwapKit request. `HTTPClientError.statusCode` renders as
/// "Status Code: 403, Data Length: 4545", which cannot tell SwapKit's own refusal (a JSON body) from
/// a page served in front of it (an HTML block page). This names the path (never the query or the
/// headers, so never the API key) and the body: an HTML page by its `<title>` (any case, with or
/// without attributes; an empty one falls back to the body), anything else by its first characters
/// on one line.
enum SwapKitFailureDetail {
    static let excerptLength = 200

    static func describe(_ error: Error) -> String {
        guard let clientError = error as? HTTPClientError, case .statusCode(let response) = clientError else {
            return error.localizedDescription
        }
        let path = response.request?.url?.path ?? "?"
        return "HTTP \(response.statusCode) \(path) (\(response.data.count) bytes): \(excerpt(of: response.data))"
    }

    private static func excerpt(of data: Data) -> String {
        guard let body = String(data: data, encoding: .utf8) else { return "<non-utf8 body>" }
        let text = title(in: body).flatMap { $0.allSatisfy(\.isWhitespace) ? nil : $0 } ?? body
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.count > excerptLength ? line.prefix(excerptLength) + "…" : line
    }

    private static func title(in html: String) -> String? {
        guard let open = html.range(of: "<title", options: .caseInsensitive),
              let tagEnd = html.range(of: ">", range: open.upperBound..<html.endIndex),
              let close = html.range(of: "</title>", options: .caseInsensitive,
                                     range: tagEnd.upperBound..<html.endIndex)
        else {
            return nil
        }
        return String(html[tagEnd.upperBound..<close.lowerBound])
    }
}

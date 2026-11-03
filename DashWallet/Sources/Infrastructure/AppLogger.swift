//
//  Created by Dash Core Group.
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
import SwiftDashSDK

/// The app's Swift logger. Shaped like `os.Logger` so call sites read the same,
/// but every line goes through `DWLogger`: into the rolling file log that
/// "Share application logs" exports, and to the console via its OSLog sink.
/// The category becomes the line's class name.
///
/// Privacy follows `os.Logger`: an interpolated integer, float or `Bool` is
/// written as is; any other value is written as `<private>` unless marked
/// `privacy: .public`. An interpolated `Error` is written as its type and
/// code only (`errorSummary(_:)`), never its description.
struct AppLogger: Sendable {
    let category: String

    init(category: String) {
        self.category = category
    }

    /// Written only in DEBUG builds, like os.Logger debug lines, which the
    /// system never persists.
    func debug(_ message: AppLogMessage) {
        attachSinks()
        DWLogger.logDebug(message.text, className: category)
    }

    func info(_ message: AppLogMessage) {
        attachSinks()
        DWLogger.log(message.text, className: category)
    }

    func notice(_ message: AppLogMessage) { info(message) }

    /// The file format carries no level, so warnings and errors also carry a
    /// text tag.
    func warning(_ message: AppLogMessage) {
        attachSinks()
        DWLogger.logWarning("WARNING " + message.text, className: category)
    }

    /// Written synchronously: the line is in the file before a crash that
    /// follows it.
    func error(_ message: AppLogMessage) {
        attachSinks()
        DWLogger.logError("ERROR " + message.text, className: category)
    }

    func fault(_ message: AppLogMessage) {
        attachSinks()
        DWLogger.logError("FAULT " + message.text, className: category)
    }

    /// `sharedInstance()` attaches the file and console sinks; a line logged
    /// before the app delegate creates it would otherwise be dropped.
    private func attachSinks() {
        _ = DWLogger.sharedInstance()
    }
}

enum AppLogPrivacy: Sendable {
    case `public`
    case `private`
}

struct AppLogMessage: ExpressibleByStringInterpolation {
    static let redacted = "<private>"

    /// An error's type, enum case name and code, a consensus rejection's code
    /// and kind, and the same for the errors it wraps. Not its description:
    /// error texts quote txids, outpoints, addresses, file paths and stored
    /// values.
    static func errorSummary(_ error: Error) -> String {
        errorSummary(error, depth: 0)
    }

    private static let maxWrappedErrors = 3

    private static func errorSummary(_ error: Error, depth: Int) -> String {
        let nsError = error as NSError
        let caseSuffix = caseName(of: error).map { ".\($0)" } ?? ""
        var summary = "\(type(of: error))\(caseSuffix) \(nsError.domain) #\(nsError.code)"
        if case .consensusRejection(let consensus, _)? = error as? PlatformWalletError {
            summary += " consensus code=\(consensus.code) kind=\(consensus.kind)"
        }
        if depth < maxWrappedErrors, let wrapped = wrappedError(of: error) {
            summary += " ← " + errorSummary(wrapped, depth: depth + 1)
        }
        return summary
    }

    /// The error an enum case carries in its payload, or an `NSError`'s
    /// underlying error.
    private static func wrappedError(of error: Error) -> Error? {
        let mirror = Mirror(reflecting: error)
        if mirror.displayStyle == .enum, let payload = mirror.children.first?.value {
            if let wrapped = payload as? Error {
                return wrapped
            }
            return Mirror(reflecting: payload).children.lazy.compactMap { $0.value as? Error }.first
        }
        if type(of: error) is NSError.Type {
            return (error as NSError).userInfo[NSUnderlyingErrorKey] as? Error
        }
        return nil
    }

    /// The case name of an enum value, without its payload, or nil when the
    /// value is not an enum or its name can only be read through a custom
    /// description.
    static func caseName(of value: Any) -> String? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .enum else { return nil }
        if let label = mirror.children.first?.label {
            return label
        }
        if value is CustomStringConvertible || value is CustomDebugStringConvertible
            || value is TextOutputStreamable {
            return nil
        }
        return String(describing: value)
    }

    let text: String

    init(stringLiteral value: String) {
        text = value
    }

    init(stringInterpolation: Interpolation) {
        text = stringInterpolation.text
    }

    struct Interpolation: StringInterpolationProtocol {
        fileprivate var text = ""

        init(literalCapacity: Int, interpolationCount: Int) {
            text.reserveCapacity(literalCapacity)
        }

        mutating func appendLiteral(_ literal: String) {
            text += literal
        }

        mutating func appendInterpolation(_ value: some BinaryInteger, privacy: AppLogPrivacy = .public) {
            append(privacy) { String(value) }
        }

        mutating func appendInterpolation(_ value: some BinaryFloatingPoint, privacy: AppLogPrivacy = .public) {
            append(privacy) { String(describing: value) }
        }

        mutating func appendInterpolation(_ value: Bool, privacy: AppLogPrivacy = .public) {
            append(privacy) { String(value) }
        }

        mutating func appendInterpolation(_ error: some Error, privacy: AppLogPrivacy = .public) {
            append(privacy) { AppLogMessage.errorSummary(error) }
        }

        mutating func appendInterpolation<T>(_ value: T, privacy: AppLogPrivacy = .private) {
            append(privacy) { String(describing: value) }
        }

        private mutating func append(_ privacy: AppLogPrivacy, _ render: () -> String) {
            text += privacy == .public ? render() : AppLogMessage.redacted
        }
    }
}

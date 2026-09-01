//
//  DashConnectDeepLink.swift
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

/// Exposes the DashConnect URI schemes to the app's Objective-C URL routing.
///
/// An app running on the same phone as the wallet cannot present a QR code for
/// the wallet to scan, so it opens the identical `dash-key:` / `dash-st:`
/// payload as a link instead. Both carriers hand the same string to
/// `ConnectionsViewModel`.
@objc(DWDashConnectDeepLink)
final class DashConnectDeepLink: NSObject {
    /// The DashConnect URI `url` carries, or `nil` when it is not one.
    ///
    /// The payload lives in the URI's opaque part and is Base58 followed by an
    /// ASCII query, neither of which `URL` percent-encodes, so
    /// `absoluteString` returns what the app emitted.
    @objc(uriFromURL:)
    static func uri(from url: URL) -> String? {
        let candidate = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard DashConnectUri.isKeyUri(candidate) || DashConnectUri.isStUri(candidate) else {
            return nil
        }

        return candidate
    }

    @objc(canHandleURL:)
    static func canHandle(_ url: URL) -> Bool {
        uri(from: url) != nil
    }
}

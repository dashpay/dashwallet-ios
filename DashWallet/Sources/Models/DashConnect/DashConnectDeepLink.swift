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
/// payload as a link instead. A `dashpay://connect` link carries an App Connect
/// request the same way. Every carrier hands the same string to
/// `ConnectionsViewModel`.
///
/// ## What this carrier does not establish
///
/// A custom URL scheme carries no authenticated caller and no web origin, so
/// nothing here identifies which app opened the link. The request supplies both
/// the contract id the approval sheet brands itself from and the ephemeral
/// public key the login credential is encrypted to, and those two are not tied
/// to each other: a request may pair a legitimate app's contract id with a key
/// the sender controls, and the sheet would show the legitimate app.
///
/// The QR protocol has the same gap — a photographed code is no more attributed
/// than a tapped link — but this carrier widens who can deliver one from "an app
/// that can put a code on a screen the user is looking at" to "any installed app,
/// or any tapped link". Closing it needs a session proof bound to
/// `appEphemeralPubKeyHash`, or an origin-bound channel, which is a protocol
/// change on both sides rather than something this boundary can add.
/// Size limits, which this boundary CAN enforce, live in `DashConnectUri` so
/// every carrier inherits them.
@objc(DWDashConnectDeepLink)
final class DashConnectDeepLink: NSObject {
    /// The DashConnect URI `url` carries, or `nil` when it is not one.
    ///
    /// The payload is Base58 in the opaque part of a `dash-key:` / `dash-st:`
    /// URI, or base64url in the query of a `dashpay://connect` URI, with the
    /// `cb` link already percent-encoded. `URL` does not re-encode either, so
    /// `absoluteString` returns what the app emitted.
    @objc(uriFromURL:)
    static func uri(from url: URL) -> String? {
        let candidate = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard DashConnectUri.isKeyUri(candidate) || DashConnectUri.isStUri(candidate)
            || DashConnectUri.isConnectUri(candidate) else {
            return nil
        }

        return candidate
    }

    @objc(canHandleURL:)
    static func canHandle(_ url: URL) -> Bool {
        uri(from: url) != nil
    }

    /// Whether `url` is a `dashpay://` link whose verb this wallet does not
    /// know, such as `sign`. The caller says the link needs a newer wallet
    /// rather than that it is not a Dash URL. Invitations and `connect` are
    /// not unsupported.
    @objc(isUnsupportedDashpayVerbURL:)
    static func isUnsupportedDashpayVerb(_ url: URL) -> Bool {
        DashConnectUri.isUnsupportedDashpayVerb(url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

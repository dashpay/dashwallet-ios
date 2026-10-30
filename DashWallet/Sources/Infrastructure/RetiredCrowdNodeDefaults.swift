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

import UIKit
import WebKit

/// Removes the UserDefaults the app's CrowdNode integration wrote, and the
/// cookies and website data its web screens left. The app no longer reads
/// any of them.
///
/// Runs once, recorded by a done flag. Before the first unlock after a reboot
/// UserDefaults can read back empty, and a flag written then would skip the
/// keys for good, so an activation without protected data leaves the work to
/// the next one.
@objc(DWRetiredCrowdNodeDefaults)
final class RetiredCrowdNodeDefaults: NSObject {
    static let doneKey = "retiredCrowdNodeDefaultsRemoved"
    /// Set only once WebKit reports the removal done, so an app killed
    /// mid-removal tries again on a later activation.
    static let websiteDataDoneKey = "retiredCrowdNodeWebsiteDataRemoved"

    /// Keys stored as written, not per wallet. The names are copied byte for
    /// byte: the online-state key starts with a Cyrillic "с" (U+0441), and
    /// some names don't mention CrowdNode at all.
    static let globalKeys: [String] = [
        "crowdNodeInfoShownKey",
        "crowdNodeWithdrawalLimitPerTxKey",
        "crowdNodeWithdrawalLimitPerHourKey",
        "crowdNodeWithdrawalLimitPerDayKey",
        "crowdNodeWithdrawalLimitsInfoShownKey",
        "feePercentageKey",
        "crowdNodeOnlineAccountAddressKey",
    ]

    /// Keys stored once per wallet as `<key>_<walletIdHex>`, and also bare
    /// by installs that predate per-wallet scoping.
    static let perWalletKeys: [String] = [
        "lastKnownCrowdNodeBalanceKey",
        "\u{0441}rowdNodeOnlineAccountStateKey",
        "crowdNodeAccountAddressKey",
        "crowdNodePrimaryAddressKey",
        "crowdNodeConfirmationDialogShownKey",
        "crowdNodeOnlineInfoShownKey",
        "crowdNodeSignedEmailMessageId",
        "shouldShowConfirmedNotification",
        "lastWithdrawalBlockKey",
        "crowdNodeFruitlessRestoreTxCountKey",
    ]

    /// Called on every activation; each part retries until it is recorded
    /// as done.
    @MainActor @objc
    static func removeAllOnce() {
        let application = UIApplication.shared
        let defaults = UserDefaults.standard
        removeAllOnce(from: defaults, isProtectedDataAvailable: application.isProtectedDataAvailable)
        if shouldRemoveWebsiteData(defaults: defaults,
                                   isProtectedDataAvailable: application.isProtectedDataAvailable,
                                   isActive: application.applicationState == .active) {
            removeWebsiteData {
                defaults.set(true, forKey: websiteDataDoneKey)
            }
        }
    }

    /// Website data goes only while the app is in the foreground: removing
    /// it starts WebKit's processes, which a background launch (refresh,
    /// push) shouldn't pay for, and iOS may suspend it before WebKit reports
    /// back. Until a removal is reported done, a later activation tries again.
    static func shouldRemoveWebsiteData(defaults: UserDefaults,
                                        isProtectedDataAvailable: Bool,
                                        isActive: Bool) -> Bool {
        isProtectedDataAvailable && isActive && !defaults.bool(forKey: websiteDataDoneKey)
    }

    /// Removes the defaults unless already recorded as done or protected data
    /// is unavailable. Returns whether it ran.
    @discardableResult
    static func removeAllOnce(from defaults: UserDefaults, isProtectedDataAvailable: Bool) -> Bool {
        guard isProtectedDataAvailable, !defaults.bool(forKey: doneKey) else { return false }
        removeAll(from: defaults)
        defaults.set(true, forKey: doneKey)
        return true
    }

    /// The service's hosts are this domain or its subdomains on every network.
    private static let webDomain = "crowdnode.io"

    /// `crowdnode.io` or a subdomain, in any letter case; a leading dot
    /// (cookie domain form) and a trailing root dot are ignored, and a name
    /// merely ending in the same letters doesn't match.
    static func isWebDomain(_ host: String) -> Bool {
        var name = host.lowercased()
        if name.hasPrefix(".") { name.removeFirst() }
        if name.hasSuffix(".") { name.removeLast() }
        return name == webDomain || name.hasSuffix("." + webDomain)
    }

    @MainActor
    private static func removeWebsiteData(completion: @escaping () -> Void) {
        let cookies = HTTPCookieStorage.shared
        for cookie in cookies.cookies ?? [] where isWebDomain(cookie.domain) {
            cookies.deleteCookie(cookie)
        }
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let retired = records.filter { isWebDomain($0.displayName) }
            guard !retired.isEmpty else {
                completion()
                return
            }
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: retired, completionHandler: completion)
        }
    }

    /// One wallet's keys, for the wiper's per-wallet deletion; the bare
    /// and other wallets' keys stay for the activation cleanup.
    static func removePerWalletKeys(forWalletIdHex walletIdHex: String,
                                    from defaults: UserDefaults = .standard) {
        for key in perWalletKeys {
            defaults.removeObject(forKey: "\(key)_\(walletIdHex)")
        }
    }

    static func removeAll(from defaults: UserDefaults) {
        for key in globalKeys + perWalletKeys {
            defaults.removeObject(forKey: key)
        }
        let prefixes = perWalletKeys.map { "\($0)_" }
        for key in defaults.dictionaryRepresentation().keys
            where prefixes.contains(where: { key.hasPrefix($0) }) {
            defaults.removeObject(forKey: key)
        }
    }
}

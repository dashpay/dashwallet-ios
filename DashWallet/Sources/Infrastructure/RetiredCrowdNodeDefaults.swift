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
/// keys for good, so a launch without protected data leaves the work to the
/// next one.
@objc(DWRetiredCrowdNodeDefaults)
final class RetiredCrowdNodeDefaults: NSObject {
    static let doneKey = "retiredCrowdNodeDefaultsRemoved"

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

    @MainActor @objc
    static func removeAllOnce() {
        let didRun = removeAllOnce(from: .standard,
                                   isProtectedDataAvailable: UIApplication.shared.isProtectedDataAvailable)
        if didRun {
            removeWebsiteData()
        }
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

    /// The service's hosts end in this domain on every network.
    private static let webDomain = "crowdnode.io"

    @MainActor
    private static func removeWebsiteData() {
        let cookies = HTTPCookieStorage.shared
        for cookie in cookies.cookies ?? [] where cookie.domain.hasSuffix(webDomain) {
            cookies.deleteCookie(cookie)
        }
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let retired = records.filter { $0.displayName.hasSuffix(webDomain) }
            guard !retired.isEmpty else { return }
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: retired) { }
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

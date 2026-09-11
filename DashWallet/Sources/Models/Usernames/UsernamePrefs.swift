//  
//  Created by Andrei Ashikhmin
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

private let kCoinJoinMixDashShown = "coinJoinMixDashShownKey"
private let kJoinDashPayInfoShown = "joinDashPayInfoShownKey"
private let kRequestedUsernameId = "requestedUsernameIdKey"
private let kAlreadyPaid = "alreadyPaidForUsernameKey"
private let kJoinDashPayDismissed = "joinDashPayDismissed"
private let kInFlightRegistrationUsername = "inFlightRegistrationUsername"
private let kCompletedTileUsername = "usernameRegistrationCompletedTile"

/// Keeps the Upgrade-to-DashPay banner dismissal attached to the wallet and
/// network where the user made that choice. A global flag leaks between
/// Mainnet and Testnet; an in-memory scalar also serves stale state after a
/// network round-trip.
enum JoinDashPayDismissalScope {
    static func storageKey(networkRawValue: Int, walletIdHex: String?) -> String {
        scopedKey(kJoinDashPayDismissed, networkRawValue: networkRawValue, walletIdHex: walletIdHex)
    }

    /// The same wallet + network scoping, for the other username-registration
    /// flags that must not leak across a network switch.
    static func scopedKey(_ base: String, networkRawValue: Int, walletIdHex: String?) -> String {
        let walletScope = walletIdHex.flatMap { $0.isEmpty ? nil : $0 } ?? "unbound"
        return "\(base).v2.\(networkRawValue).\(walletScope)"
    }
}

// MARK: - UsernamePrefs

class UsernamePrefs {
    public static let shared: UsernamePrefs = .init()
    
    private var _mixDashShown: Bool? = nil
    var mixDashShown: Bool {
        get { _mixDashShown ?? UserDefaults.standard.bool(forKey: kCoinJoinMixDashShown) }
        set(value) {
            _mixDashShown = value
            UserDefaults.standard.set(value, forKey: kCoinJoinMixDashShown)
        }
    }
    
    private var _joinDashPayInfoShown: Bool? = nil
    var joinDashPayInfoShown: Bool {
        get { _joinDashPayInfoShown ?? UserDefaults.standard.bool(forKey: kJoinDashPayInfoShown) }
        set(value) {
            _joinDashPayInfoShown = value
            UserDefaults.standard.set(value, forKey: kJoinDashPayInfoShown)
        }
    }
    
    private var _requestedUsernameId: String? = nil
    var requestedUsernameId: String? {
        get { _requestedUsernameId ?? UserDefaults.standard.string(forKey: kRequestedUsernameId) }
        set(value) {
            _requestedUsernameId = value
            UserDefaults.standard.set(value, forKey: kRequestedUsernameId)
        }
    }
    
    private var _alreadyPaid: Bool? = nil
    var alreadyPaid: Bool {
        get { _alreadyPaid ?? UserDefaults.standard.bool(forKey: kAlreadyPaid) }
        set(value) {
            _alreadyPaid = value
            UserDefaults.standard.set(value, forKey: kAlreadyPaid)
        }
    }
    
    var joinDashPayDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: joinDashPayDismissedKey) }
        set(value) {
            UserDefaults.standard.set(value, forKey: joinDashPayDismissedKey)
        }
    }

    private var joinDashPayDismissedKey: String {
        JoinDashPayDismissalScope.storageKey(
            networkRawValue: WalletEnvironment.networkKind.rawValue,
            walletIdHex: WalletEnvironment.activeWalletIdHex as String?)
    }

    /// The label of a registration that was handed off to the Home tile and has
    /// not reached a terminal state yet.
    ///
    /// The SDK persists the *money* side of a Core-funded attempt (the
    /// asset-lock recovery row, the identity row) but nothing persists the
    /// label once the SwiftUI form is used — `submitUsernameRequest` goes
    /// straight to the bridge, and the `DWGlobalOptions` mirror is written only
    /// on completion. Without this record, an app killed mid-registration comes
    /// back showing the "Upgrade to DashPay" call to action to a user whose
    /// funds may already be spent, which is indistinguishable from never having
    /// tried.
    var inFlightRegistrationUsername: String? {
        get { UserDefaults.standard.string(forKey: inFlightRegistrationUsernameKey) }
        set(value) {
            if let value, !value.isEmpty {
                UserDefaults.standard.set(value, forKey: inFlightRegistrationUsernameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: inFlightRegistrationUsernameKey)
            }
        }
    }

    private var inFlightRegistrationUsernameKey: String {
        JoinDashPayDismissalScope.scopedKey(
            kInFlightRegistrationUsername,
            networkRawValue: WalletEnvironment.networkKind.rawValue,
            walletIdHex: WalletEnvironment.activeWalletIdHex as String?)
    }

    /// The username whose registration finished and whose success tile the user
    /// has not acted on yet. Cleared when they open the profile from it or
    /// dismiss it.
    ///
    /// A name rather than an acknowledged flag because the bridge drops
    /// `currentUsername` once the registration is done: with only a flag, the
    /// next status notification would have nothing to rebuild the success tile
    /// from and would wipe it before the user ever saw it. Presence here is
    /// also what distinguishes "just registered" from "registered long ago" —
    /// the latter has no record, so no tile.
    var completedTileUsername: String? {
        get { UserDefaults.standard.string(forKey: completedTileUsernameKey) }
        set(value) {
            if let value, !value.isEmpty {
                UserDefaults.standard.set(value, forKey: completedTileUsernameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: completedTileUsernameKey)
            }
        }
    }

    private var completedTileUsernameKey: String {
        JoinDashPayDismissalScope.scopedKey(
            kCompletedTileUsername,
            networkRawValue: WalletEnvironment.networkKind.rawValue,
            walletIdHex: WalletEnvironment.activeWalletIdHex as String?)
    }
}

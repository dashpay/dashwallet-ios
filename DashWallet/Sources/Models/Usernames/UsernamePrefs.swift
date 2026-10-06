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
private let kLostContestUsername = "lostContestUsername"
private let kLostContestWasBlocked = "lostContestWasBlocked"
private let kCompletedTileUsername = "usernameRegistrationCompletedTile"
private let kFailedCompanion = "failedCompanionUsernameRecord"
private let kAcceptedFundingSource = "usernameAcceptedFundingSource"

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
        scoped(kInFlightRegistrationUsername)
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

    /// The contested name this wallet asked for and did NOT get — its vote
    /// ended in someone else's favour or in a lock. Which of the two is in
    /// `lostContestWasBlocked`.
    ///
    /// Kept for the same reason as `completedTileUsername`: when the bookmark
    /// is cleared the row has nothing left to report from, and the loss went
    /// straight back to "Join DashPay — request your username" as if the
    /// request had never happened. Cleared when the user acts on the row
    /// (retry) or dismisses it.
    var lostContestUsername: String? {
        get { UserDefaults.standard.string(forKey: lostContestUsernameKey) }
        set(value) {
            if let value, !value.isEmpty {
                UserDefaults.standard.set(value, forKey: lostContestUsernameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lostContestUsernameKey)
            }
        }
    }

    /// `true` when `lostContestUsername` was locked by the network rather
    /// than won by another identity.
    ///
    /// The two outcomes are not interchangeable advice: a locked name is
    /// gone for everyone and asking for it again achieves nothing, while a
    /// name given to someone else is simply taken. Written together with
    /// `lostContestUsername` and cleared with it.
    var lostContestWasBlocked: Bool {
        get { UserDefaults.standard.bool(forKey: lostContestWasBlockedKey) }
        set(value) {
            if value {
                UserDefaults.standard.set(true, forKey: lostContestWasBlockedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lostContestWasBlockedKey)
            }
        }
    }

    private var lostContestWasBlockedKey: String {
        scoped(kLostContestWasBlocked)
    }

    private var lostContestUsernameKey: String {
        scoped(kLostContestUsername)
    }

    private var completedTileUsernameKey: String {
        scoped(kCompletedTileUsername)
    }

    // MARK: - Instant (companion) username failure

    /// The instant username that failed to register next to a contested
    /// request, the contested label it was asked for with, and why.
    ///
    /// The contested request still goes in when its companion fails, and the
    /// form hands the outcome to the status row before it is known, so this
    /// record is what lets Request details tell the user and offer a retry.
    /// Scoped to the wallet and network like the other registration records;
    /// cleared once a request for another name is written to Platform, when
    /// the instant name itself registers, when the contest resolves, or when
    /// Request details finds the name owned. `reason` is the raw error, worded
    /// when shown.
    struct FailedCompanion: Equatable, Codable {
        let username: String
        let contestedLabel: String
        let reason: String
    }

    /// One scoped key holding the whole record, so it is written and cleared
    /// as a unit.
    var failedCompanion: FailedCompanion? {
        get {
            guard let data = UserDefaults.standard.data(forKey: scoped(kFailedCompanion)) else { return nil }
            return try? JSONDecoder().decode(FailedCompanion.self, from: data)
        }
        set(value) {
            if let value, let data = try? JSONEncoder().encode(value) {
                UserDefaults.standard.set(data, forKey: scoped(kFailedCompanion))
            } else {
                UserDefaults.standard.removeObject(forKey: scoped(kFailedCompanion))
            }
        }
    }

    /// Clears the record when it belongs to the request for `contestedLabel`.
    func clearFailedCompanion(forContestedLabel contestedLabel: String) {
        if let failed = failedCompanion,
           DWContestedNameStatusService.labelsMatch(failed.contestedLabel, contestedLabel) {
            failedCompanion = nil
        }
    }

    /// Clears the record when `username` belongs to another request — neither
    /// the instant name it reports (its retry) nor the contested name it was
    /// asked with (that request driven again). A request for anything else
    /// retires it.
    func clearFailedCompanion(unlessUsername username: String) {
        if let failed = failedCompanion,
           !DWContestedNameStatusService.labelsMatch(failed.username, username),
           !DWContestedNameStatusService.labelsMatch(failed.contestedLabel, username) {
            failedCompanion = nil
        }
    }

    /// Clears the record when it is for the instant name `username`.
    func clearFailedCompanion(forUsername username: String) {
        if let failed = failedCompanion,
           DWContestedNameStatusService.labelsMatch(failed.username, username) {
            failedCompanion = nil
        }
    }

    private func scoped(_ base: String) -> String {
        JoinDashPayDismissalScope.scopedKey(
            base,
            networkRawValue: WalletEnvironment.networkKind.rawValue,
            walletIdHex: WalletEnvironment.activeWalletIdHex as String?)
    }

    // MARK: - Accepted funding source

    /// The funding source a request went out with, kept per label from the
    /// moment it is submitted until it completes. A retry opens a fresh form,
    /// which has no memory of the privacy-page pick: it reuses this source
    /// while the source can pay, and asks before paying from another one.
    func acceptedFundingSourceRaw(forLabel label: String) -> Int? {
        acceptedFundingSources[DWContestedNameStatusService.dpnsKey(label)]
    }

    func recordAcceptedFundingSourceRaw(_ raw: Int, forLabel label: String) {
        var entries = acceptedFundingSources
        entries[DWContestedNameStatusService.dpnsKey(label)] = raw
        UserDefaults.standard.set(entries, forKey: scoped(kAcceptedFundingSource))
    }

    func clearAcceptedFundingSource(forLabel label: String) {
        var entries = acceptedFundingSources
        guard entries.removeValue(forKey: DWContestedNameStatusService.dpnsKey(label)) != nil else { return }
        if entries.isEmpty {
            UserDefaults.standard.removeObject(forKey: scoped(kAcceptedFundingSource))
        } else {
            UserDefaults.standard.set(entries, forKey: scoped(kAcceptedFundingSource))
        }
    }

    private var acceptedFundingSources: [String: Int] {
        (UserDefaults.standard.dictionary(forKey: scoped(kAcceptedFundingSource)) as? [String: Int]) ?? [:]
    }

    /// Drops `label`'s record for `walletId` on every network, whichever
    /// wallet is active: a request completes for the wallet that made it.
    static func clearAcceptedFundingSource(forLabel label: String, walletId: Data) {
        let defaults = UserDefaults.standard
        let labelKey = DWContestedNameStatusService.dpnsKey(label)
        for key in acceptedFundingSourceKeys(walletId: walletId) {
            guard var entries = defaults.dictionary(forKey: key) as? [String: Int],
                  entries.removeValue(forKey: labelKey) != nil else { continue }
            if entries.isEmpty {
                defaults.removeObject(forKey: key)
            } else {
                defaults.set(entries, forKey: key)
            }
        }
    }

    /// Every record of `walletId` (every wallet's when nil): re-adding the
    /// same seed gets the same wallet id, and must not inherit a pick from
    /// before the wallet was removed or the device wiped.
    static func resetAcceptedFundingSources(walletId: Data? = nil) {
        let defaults = UserDefaults.standard
        for key in acceptedFundingSourceKeys(walletId: walletId) {
            defaults.removeObject(forKey: key)
        }
    }

    private static func acceptedFundingSourceKeys(walletId: Data?) -> [String] {
        let suffix = walletId.map { "." + $0.hexEncodedString() }
        return UserDefaults.standard.dictionaryRepresentation().keys.filter { key in
            key.hasPrefix(kAcceptedFundingSource) && (suffix.map { key.hasSuffix($0) } ?? true)
        }
    }
}

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

/// More → Security → Advanced Security: auto logout with its lock timer, and
/// spending confirmation with its biometric limit, plus the security level
/// they add up to.
@MainActor
final class AdvancedSecurityViewModel: ObservableObject {
    /// Immediately (the lock timer off), 1 min, 5 min, 1 hour, 24 hours.
    nonisolated static let lockTimerIntervals = [0, 60, 60 * 5, 60 * 60, 60 * 60 * 24]
    /// 0, 0.1, 0.5, 1 and 5 Dash, in duffs.
    nonisolated static let spendingLimits: [UInt64] = [0, kOneDash / 10, kOneDash / 2, kOneDash, kOneDash * 5]

    nonisolated static let defaultLockTimerInterval = 60
    /// Also what enabling biometrics in the Security menu sets.
    nonisolated static let defaultSpendingLimit = kOneDash / 2

    @Published private(set) var autoLogout = false
    /// Position of the stored lock timer in `lockTimerIntervals`; `nil` when
    /// the stored value isn't one of them.
    @Published private(set) var lockTimerIndex: Int?
    @Published private(set) var spendingConfirmationEnabled = false
    /// Position of the stored limit in `spendingLimits`; `nil` when no limit
    /// is stored or it isn't one of them.
    @Published private(set) var spendingLimitIndex: Int?
    @Published private(set) var canConfigureSpendingConfirmation = false

    /// `false` for the onboarding preview, which only shows the settings.
    let isInteractive: Bool

    private let store: AdvancedSecuritySettingsStore

    init(store: AdvancedSecuritySettingsStore, isInteractive: Bool = true) {
        self.store = store
        self.isInteractive = isInteractive
        reload()
    }

    // MARK: - State

    var securityLevel: WalletSecurityLevel {
        WalletSecurityLevel.level(
            lockTime: autoLogout ? store.lockTimerInterval : nil,
            spendingLimit: spendingConfirmationEnabled ? storedLimit : nil)
    }

    /// The slider for the lock timer shows while auto logout is on.
    var showsLockTimer: Bool { autoLogout }

    /// The slider for the limit shows while spending confirmation is on and
    /// biometrics are enabled.
    var showsSpendingLimit: Bool { canConfigureSpendingConfirmation && spendingConfirmationEnabled }

    var biometry: AdvancedSecurityBiometry { store.biometry }

    // MARK: - Actions

    func setAutoLogout(_ isOn: Bool) {
        store.autoLogout = isOn
        reload()
    }

    func selectLockTimer(at index: Int) {
        guard Self.lockTimerIntervals.indices.contains(index) else { return }
        store.lockTimerInterval = Self.lockTimerIntervals[index]
        reload()
    }

    func setSpendingConfirmation(_ isOn: Bool) {
        store.spendingConfirmationEnabled = isOn
        reload()
    }

    func selectSpendingLimit(at index: Int) {
        guard Self.spendingLimits.indices.contains(index) else { return }
        store.setSpendingLimit(Self.spendingLimits[index])
        // Re-read: the store refuses the change when it may not be made now.
        reload()
    }

    func resetToDefault() {
        store.autoLogout = true
        store.lockTimerInterval = Self.defaultLockTimerInterval
        store.spendingConfirmationEnabled = true
        store.setSpendingLimit(Self.defaultSpendingLimit)
        reload()
    }

    // MARK: - Copy

    var lockTimerTitle: String {
        store.lockTimerInterval == 0
            ? NSLocalizedString("Logout", comment: "a verb, Logout Immediately")
            : NSLocalizedString("Logout after", comment: "Logout after 5 min")
    }

    /// The stored lock timer, spelled out, including a value that is not a
    /// slider stop.
    var lockTimerValueText: String { Self.lockTimerText(store.lockTimerInterval) }

    static func lockTimerText(_ seconds: Int) -> String {
        switch seconds {
        case 0: return NSLocalizedString("Immediately", comment: "")
        case 60: return NSLocalizedString("1 min", comment: "Shorten version of minute")
        case 60 * 5: return NSLocalizedString("5 min", comment: "Shorten version of minutes")
        case 60 * 60: return NSLocalizedString("1 hour", comment: "")
        case 60 * 60 * 24: return NSLocalizedString("24 hours", comment: "")
        default:
            // Not a slider stop: only a value stored by an older build.
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.string(from: TimeInterval(seconds)) ?? ""
        }
    }

    var spendingLimitTitle: String {
        switch store.biometry {
        case .touchID: return NSLocalizedString("Touch ID limit", comment: "")
        case .faceID: return NSLocalizedString("Face ID limit", comment: "")
        case .none: return ""
        }
    }

    /// The sentence under the limit slider. When `descriptionShowsAmount`,
    /// the view appends the limit amount after it.
    var spendingLimitDescription: String {
        // No stored limit says nothing about the biometric allowance the
        // authentication layer applies, so the sentence promises nothing.
        guard let storedLimit else {
            return NSLocalizedString("No biometric spending limit is set", comment: "Advanced Security: no biometric spending limit stored")
        }
        // A zero limit leaves no allowance: every payment asks for the PIN.
        if storedLimit == 0 {
            return NSLocalizedString("PIN is always required to make a payment", comment: "")
        }
        switch store.biometry {
        case .touchID: return NSLocalizedString("You can authenticate with Touch ID for payments below", comment: "")
        case .faceID: return NSLocalizedString("You can authenticate with Face ID for payments below", comment: "")
        case .none: return NSLocalizedString("You can authenticate with biometrics for payments below", comment: "")
        }
    }

    /// The stored limit, spelled out, including a value that is not a slider
    /// stop; "None" when no limit is stored.
    var spendingLimitValueText: String {
        guard let storedLimit else { return NSLocalizedString("None", comment: "") }
        return Int64(clamping: storedLimit).formattedDashAmount
    }

    /// Whether the description ends with the limit amount.
    var descriptionShowsAmount: Bool { (storedLimit ?? 0) != 0 }

    /// The stored limit as a signed amount for display, `nil` when none is set.
    var spendingLimitAmount: Int64? { storedLimit.map { Int64(clamping: $0) } }

    // MARK: - Private

    /// The stored limit, `nil` when none was ever set.
    private var storedLimit: UInt64? {
        let limit = store.spendingLimit
        return limit == AuthenticationService.spendingLimitNotSet ? nil : limit
    }

    private func reload() {
        autoLogout = store.autoLogout
        lockTimerIndex = Self.lockTimerIntervals.firstIndex(of: store.lockTimerInterval)
        spendingConfirmationEnabled = store.spendingConfirmationEnabled
        spendingLimitIndex = storedLimit.flatMap { Self.spendingLimits.firstIndex(of: $0) }
        canConfigureSpendingConfirmation = store.canConfigureSpendingConfirmation
    }
}

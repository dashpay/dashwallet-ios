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

import LocalAuthentication
import UIKit

/// The biometry the spending-confirmation copy names.
enum AdvancedSecurityBiometry {
    case touchID
    case faceID
    case none
}

/// Where the Advanced Security settings are read from and written to.
@MainActor
protocol AdvancedSecuritySettingsStore: AnyObject {
    var autoLogout: Bool { get set }
    /// Seconds before the app locks while auto logout is on.
    var lockTimerInterval: Int { get set }
    var spendingConfirmationEnabled: Bool { get set }
    /// Whether the biometric spending limit can be set (biometrics enabled).
    var canConfigureSpendingConfirmation: Bool { get }
    /// Duffs spendable with biometrics; `AuthenticationService.spendingLimitNotSet`
    /// when no limit was ever stored.
    var spendingLimit: UInt64 { get }
    /// Stores the limit if it may be changed now; `spendingLimit` reflects
    /// whether it was.
    func setSpendingLimit(_ duffs: UInt64)
    var biometry: AdvancedSecurityBiometry { get }
}

/// The wallet's real settings: lock-screen and spending-confirmation options
/// in `DWGlobalOptions`, the biometric limit in `AuthenticationService`.
@MainActor
final class LiveAdvancedSecuritySettingsStore: AdvancedSecuritySettingsStore {
    private let options = DWGlobalOptions.sharedInstance()
    private let authentication = AuthenticationService.shared

    var autoLogout: Bool {
        get { !options.lockScreenDisabled() }
        set { options.setLockScreenDisabled(!newValue) }
    }

    var lockTimerInterval: Int {
        get { options.autoLockAppInterval }
        set { options.autoLockAppInterval = newValue }
    }

    var spendingConfirmationEnabled: Bool {
        get { !options.spendingConfirmationDisabled() }
        set { options.setSpendingConfirmationDisabled(!newValue) }
    }

    var canConfigureSpendingConfirmation: Bool { options.biometricAuthEnabled }

    var spendingLimit: UInt64 { authentication.biometricSpendingLimit }

    func setSpendingLimit(_ duffs: UInt64) {
        // Refused unless the user authenticated this session; the getter
        // then still returns the stored limit.
        authentication.setBiometricSpendingLimitIfAuthenticated(duffs)
    }

    var biometry: AdvancedSecurityBiometry {
        if authentication.touchIDEnabled { return .touchID }
        if authentication.faceIDEnabled { return .faceID }
        return .none
    }
}

/// The onboarding preview: the recommended settings, held in memory so the
/// demo never reads or changes the wallet's own.
@MainActor
final class DemoAdvancedSecuritySettingsStore: AdvancedSecuritySettingsStore {
    var autoLogout = true
    var lockTimerInterval = 60
    var spendingConfirmationEnabled = true
    private(set) var spendingLimit = kOneDash / 2
    let canConfigureSpendingConfirmation: Bool
    let biometry: AdvancedSecurityBiometry

    init() {
        #if SNAPSHOT
        canConfigureSpendingConfirmation = true
        // Screenshots show Face ID on devices with a home indicator.
        let window = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first
        biometry = (window?.safeAreaInsets.bottom ?? 0) > 0 ? .faceID : .touchID
        #else
        canConfigureSpendingConfirmation = DWBiometricAuthModel.biometricAuthenticationAvailable
        switch DWBiometricAuthModel().biometryType {
        case .touchID: biometry = .touchID
        case .faceID: biometry = .faceID
        default: biometry = .none
        }
        #endif
    }

    func setSpendingLimit(_ duffs: UInt64) {
        spendingLimit = duffs
    }
}

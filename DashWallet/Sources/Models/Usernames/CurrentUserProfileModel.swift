//  
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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
import Combine

@objc(DWCurrentUserProfileModelState)
enum CurrentUserProfileModelState: Int {
    case none
    case loading
    case done
    case error
}

@objc(DWCurrentUserProfileModel)
class CurrentUserProfileModel: NSObject, ObservableObject {
    private var cancellableBag = Set<AnyCancellable>()
    private var model = SyncModelImpl()
    @objc private(set) var state: CurrentUserProfileModelState = .none
    @objc let updateModel: DWDPUpdateProfileModel
    @Published private(set) var showJoinDashpay: Bool = false
    /// Chain still catching up. The Join DashPay row stays visible throughout
    /// (it is a standing menu entry) but presents itself as unavailable:
    /// registration cannot be started until the chain is synced.
    @Published private(set) var isSyncing: Bool = false

    override init() {
        updateModel = DWDPUpdateProfileModel()
        super.init()

        model.$state
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.isSyncing = state != .syncDone
                self?.updateShowJoinDashpay()
            }
            .store(in: &cancellableBag)

        // Registration (or the Identities screen adopting a discovered
        // identity) retires the banner live — both paths post the
        // registration-status update after writing the username mirror.
        NotificationCenter.default.publisher(for: .DWDashPayRegistrationStatusUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateShowJoinDashpay()
            }
            .store(in: &cancellableBag)

        // Re-evaluate only after the SDK host has rebound to the destination
        // network. This prevents the menu banner from inheriting the previous
        // network's global username mirror.
        NotificationCenter.default.publisher(
            for: SwiftDashSDKWalletState.activeWalletDidChangeNotification
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.updateShowJoinDashpay()
        }
        .store(in: &cancellableBag)

        NotificationCenter.default.publisher(for: NSNotification.Name.DWCurrentNetworkDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showJoinDashpay = false
            }
            .store(in: &cancellableBag)

        updateShowJoinDashpay()
    }

    /// The menu's Join DashPay banner: only while synced AND not already
    /// registered. "Registered" is the SDK truth
    /// (`DWCurrentUserIdentityInfo`, which also backfills the
    /// `DWGlobalOptions.dashpayUsername` mirror when it finds a name the
    /// mirror missed) OR the mirror itself — the mirror alone misses
    /// identities that synced in without completing registration on this
    /// install, which kept the banner up on a wallet that already has a
    /// username.
    private func updateShowJoinDashpay() {
        let identityState = MainActor.assumeIsolated {
            let identity = DWCurrentUserIdentityInfo.shared
            return (
                contextReady: identity.isCurrentNetworkContextReady,
                hasIdentity: identity.hasIdentity,
                username: identity.username
            )
        }
        let options = DWGlobalOptions.sharedInstance()
        let hasUsername = JoinDashPayRegistrationPolicy.hasRegisteredUsername(
            hasIdentity: identityState.hasIdentity,
            sdkUsername: identityState.username,
            legacyRegistrationCompleted: options.dashpayRegistrationCompleted,
            legacyUsername: options.dashpayUsername)
        let hasPendingRecoveredName = MainActor.assumeIsolated {
            DWContestedNameStatusService.shared.pendingLabel != nil
        }
        showJoinDashpay = JoinDashPayBannerPolicy.shouldShow(
            contextReady: identityState.contextReady,
            // Not gated on sync. The More entry is a standing menu row, and
            // gating it made it come and go depending on how far the chain
            // had caught up — the row was simply absent for the whole of a
            // long sync. Registration itself still needs a synced chain; the
            // row reflects that in its own copy rather than by vanishing.
            syncDone: true,
            // Deliberately not `UsernamePrefs.shared.joinDashPayDismissed`.
            // That flag is set by the close control, which exists only on
            // Home — the More entry has no dismiss affordance at all. Reading
            // it here meant one tap on Home's close permanently removed the
            // menu entry too, with no way for the user to bring it back.
            // On More the banner is a standing menu row: it disappears when
            // the user actually has a username, not when they dismiss it.
            dismissed: false,
            hasRegisteredUsername: hasUsername,
            hasRegistrationInProgress: hasPendingRecoveredName)
    }

    /// Re-evaluates the menu banner after a local preference change such as
    /// tapping Hide. Unlike sync/network notifications, preference writes do
    /// not otherwise publish an event to this profile model.
    func refreshJoinDashPayBanner() {
        updateShowJoinDashpay()
    }
    
    @objc @MainActor func update() {
        DWCurrentUserIdentityInfo.shared.refreshFromSDK()
        let options = DWGlobalOptions.sharedInstance()
        let hasIdentity = DWCurrentUserIdentityInfo.shared.hasIdentity
            || options.dashpayRegistrationCompleted
            || options.dashpayUsername?.isEmpty == false
        state = hasIdentity ? .done : .none
    }
}

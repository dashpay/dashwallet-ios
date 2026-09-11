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

import Combine
import Foundation

extension Notification.Name {
    /// A username registration has been handed from the create screen to the
    /// Home row. Its own event rather than a re-post of the registration
    /// status: the status has not changed, the surface reporting it has.
    static let DWUsernameRegistrationHandedOff = Notification.Name("DWUsernameRegistrationHandedOff")
}

class JoinDashPayViewModel: ObservableObject {
    private let initialState: JoinDashPayState
    @Published private(set) var state: JoinDashPayState
    @Published private(set) var username: String = ""
    /// Which of the three registration stages `.creating` and
    /// `.creationFailed` refer to. Meaningless in every other state.
    @Published private(set) var registrationStep: DWDPRegistrationState = .processingPayment

    private var cancellableBag = Set<AnyCancellable>()

    init(initialState: JoinDashPayState, username: String = "") {
        self.initialState = initialState
        self.state = initialState
        self.username = username
        observeRegistration()
    }

    @MainActor
    func checkUsername() {
        let identity = DWCurrentUserIdentityInfo.shared
        let options = DWGlobalOptions.sharedInstance()

        if let report = registrationReport() {
            // A registration this wallet started outranks everything else the
            // row could say: it is the only surface reporting on it.
            self.state = report.state
            self.username = report.username
            self.registrationStep = report.step
        } else if let pending = DWContestedNameStatusService.shared.pendingLabel {
            // Same-seed recovery reconstructs this bookmark from Platform.
            // Surface the real voting state instead of offering Join DashPay
            // for an identity that already has a submitted name.
            self.state = .voting
            self.username = pending
        } else if let registeredUsername = identity.username ?? options.dashpayUsername,
                  identity.hasIdentity || options.dashpayRegistrationCompleted,
                  UsernamePrefs.shared.joinDashPayDismissed {
            self.state = .registered
            self.username = registeredUsername
        } else {
            self.state = initialState
        }
    }

    /// The X on the row, and the tap that acts on a finished registration.
    ///
    /// What "dismissed" means depends on what the row was showing. For a
    /// registration report the record behind it is dropped — the user loses
    /// nothing, a Core-funded attempt's recovery lock is persisted SDK-side
    /// and the create screen still surfaces it through
    /// `hasPendingRegistrationRecovery` on the next visit. For the call to
    /// action it is the persisted per-wallet dismissal, as before.
    @MainActor
    func markAsDismissed() {
        let prefs = UsernamePrefs.shared
        switch state {
        case .creating, .creationFailed, .interrupted:
            prefs.inFlightRegistrationUsername = nil
            prefs.completedTileUsername = nil
        case .approved:
            // Acting on the success is also what settles the banner into
            // `.registered`, the state a registered user's row rests in.
            prefs.completedTileUsername = nil
            prefs.joinDashPayDismissed = true
        case .none, .callToAction, .voting, .failed, .blocked, .contested, .registered:
            prefs.joinDashPayDismissed = true
        }
        self.checkUsername()
    }

    // MARK: - Registration handoff

    /// Records that the create screen has stepped aside for `username` and the
    /// Home row now owns reporting it. Called from `performSubmit` once the
    /// registration is actually running, which is after the PIN gate.
    ///
    /// The row keys off this record rather than off bridge activity alone,
    /// because the bridge also carries registrations that keep their own
    /// screen. A contested submission is the case that forces this: it stays
    /// on the create screen through to the voting explanation, yet the label
    /// the bridge reports for it is the *temporary companion* name, which is
    /// not contested and so cannot be told apart by inspecting the label.
    /// Without this gate the user would get a Home report and a blocking
    /// screen for one operation.
    /// Which wallet and network the registration the BRIDGE is currently
    /// running belongs to.
    ///
    /// The persisted handoff is already wallet/network-scoped, but the bridge
    /// is a process-global whose username and terminal state survive a network
    /// switch. Two scopes can hold the same label — a registration that fails
    /// on mainnet and the same name succeeding on testnet — and the label alone
    /// then lets mainnet read testnet's completion as its own, clearing its
    /// pending report and persisting a success for an identity it does not
    /// have. Process-global like the bridge it qualifies, so a relaunch clears
    /// both together and the persisted record decides instead.
    @MainActor private static var handedOffScope: RegistrationScope?

    private struct RegistrationScope: Equatable {
        let networkRawValue: Int
        let walletIdHex: String?

        @MainActor
        static var current: RegistrationScope {
            RegistrationScope(
                networkRawValue: WalletEnvironment.networkKind.rawValue,
                walletIdHex: WalletEnvironment.activeWalletIdHex as String?)
        }
    }

    @MainActor
    static func markRegistrationHandedOff(username: String) {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        handedOffScope = RegistrationScope.current
        UsernamePrefs.shared.inFlightRegistrationUsername = trimmed
        UsernamePrefs.shared.completedTileUsername = nil
        // Without this the row would wait for the registration's next phase
        // change to notice the record, leaving Home showing the call to action
        // for an attempt that is already running.
        NotificationCenter.default.post(name: .DWUsernameRegistrationHandedOff, object: nil)
    }

    private struct RegistrationReport {
        let state: JoinDashPayState
        let username: String
        let step: DWDPRegistrationState
    }

    /// What the row says about a registration handed off to it, or `nil`
    /// when there is none to report.
    @MainActor
    private func registrationReport() -> RegistrationReport? {
        let prefs = UsernamePrefs.shared
        let bridge = DWIdentityRegistrationBridge.shared
        let handedOff = prefs.inFlightRegistrationUsername

        // Only the registration this row was handed (see
        // `markRegistrationHandedOff`). Contested submissions and invitation
        // claims travel the same bridge but keep their own screen, and must
        // not raise a second report here.
        if let username = bridge.currentUsername,
           !username.isEmpty,
           username == handedOff,
           // The bridge's state belongs to whichever wallet and network
           // started it; on any other, this label is a different attempt.
           Self.handedOffScope == RegistrationScope.current {
            if bridge.isCompleted {
                return complete(username)
            }
            return RegistrationReport(
                state: bridge.isFailed ? .creationFailed : .creating,
                username: username,
                step: bridge.currentState)
        }

        // Nothing is running. Either a finished registration is still waiting
        // to be acted on, or an attempt was recorded and never came back.
        if let completed = prefs.completedTileUsername, !completed.isEmpty {
            return RegistrationReport(state: .approved, username: completed, step: .done)
        }

        guard let pending = prefs.inFlightRegistrationUsername, !pending.isEmpty else {
            return nil
        }

        // The attempt may well have landed while the app was dead — the
        // registration runs in the coordinator and the last leg is Platform's,
        // not ours. If an identity and name now resolve, report the success
        // the user never got to see.
        let identity = DWCurrentUserIdentityInfo.shared
        if identity.hasIdentity, let registered = identity.username, !registered.isEmpty {
            return complete(registered)
        }

        // Otherwise the honest answer is that we do not know how far it got:
        // the coordinator is `.idle` after a relaunch and there is no step to
        // claim. Resuming is the user's call — it re-enters the PIN gate,
        // which must never fire on its own at launch.
        return RegistrationReport(state: .interrupted, username: pending, step: .processingPayment)
    }

    /// The in-flight record becomes the completed one: the bridge drops
    /// `currentUsername` once a registration is done, so without a record of
    /// its own the success would be wiped by the next status notification
    /// before the user ever saw it.
    private func complete(_ username: String) -> RegistrationReport {
        let prefs = UsernamePrefs.shared
        prefs.inFlightRegistrationUsername = nil
        prefs.completedTileUsername = username
        return RegistrationReport(state: .approved, username: username, step: .done)
    }

    /// Listens to the canonical `DWDashPayModel` notification rather than
    /// subscribing to `DWIdentityRegistrationCoordinator.$phase` directly.
    ///
    /// The bridge exists precisely to serialise "mirror the state, then
    /// announce it" — a second direct subscriber would race the mirror and
    /// read a phase the cached fields have not caught up with. It is also the
    /// signal `HomeViewModel` and `MainTabbarController` already act on, so
    /// all three surfaces move on the same tick.
    private func observeRegistration() {
        let triggers: [Notification.Name] = [
            .DWDashPayRegistrationStatusUpdated,
            .DWUsernameRegistrationHandedOff,
            // Both records are scoped per wallet + network, so a switch
            // changes which keys are read. Nothing recomputes them on its own.
            SwiftDashSDKWalletState.activeWalletDidChangeNotification
        ]
        for name in triggers {
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.checkUsername()
                    }
                }
                .store(in: &cancellableBag)
        }
    }
}

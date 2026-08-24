//
//  Created by Roman Chornyi
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

import Combine
import Foundation

#if DASHPAY

extension Notification.Name {
    /// A username registration has been handed from the create screen to the
    /// Home tile. Its own event rather than a re-post of the registration
    /// status: the status has not changed, the surface reporting it has.
    static let DWUsernameRegistrationHandedOff = Notification.Name("DWUsernameRegistrationHandedOff")
}

/// Drives `UsernameRegistrationTile` — the Home surface a username
/// registration reports on once it stops holding the create screen.
///
/// Reads the registration's state, owns the record that lets the tile survive
/// process death, and owns nothing else: every string and progress fraction it
/// eventually draws belongs to `DWDPRegistrationStatus`.
@MainActor
final class UsernameRegistrationTileModel: ObservableObject {
    @Published private(set) var state: UsernameTileState = .hidden

    /// Fired after every state change so `HomeViewModel` can re-evaluate
    /// whether the Join DashPay banner may show — the tile and that banner
    /// compete for one slot.
    var onStateChange: (() -> Void)?

    private let prefs = UsernamePrefs.shared
    private var cancellableBag = Set<AnyCancellable>()

    init() {
        reload()
        observe()
    }

    // MARK: - Inputs

    /// Listens to the canonical `DWDashPayModel` notification rather than
    /// subscribing to `DWIdentityRegistrationCoordinator.$phase` directly.
    ///
    /// The bridge exists precisely to serialise "mirror the state, then
    /// announce it" — a second direct subscriber would race the mirror and read
    /// a phase the cached fields have not caught up with. It is also the signal
    /// `HomeViewModel` and `MainTabbarController` already act on, so all three
    /// surfaces move on the same tick.
    private func observe() {
        NotificationCenter.default.publisher(for: .DWDashPayRegistrationStatusUpdated)
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellableBag)

        NotificationCenter.default.publisher(for: .DWUsernameRegistrationHandedOff)
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellableBag)

        // Both records are scoped per wallet + network, so a switch changes
        // which keys are read. Nothing recomputes them on its own.
        NotificationCenter.default.publisher(for: SwiftDashSDKWalletState.activeWalletDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellableBag)
    }

    // MARK: - Handoff

    /// Records that the create screen has stepped aside for `username` and this
    /// tile now owns reporting it. Called from `performSubmit` once the
    /// registration is actually running, which is after the PIN gate.
    ///
    /// The tile keys off this record rather than off bridge activity alone,
    /// because the bridge also carries registrations that keep their own
    /// screen. A contested submission is the case that forces this: it stays on
    /// the create screen through to the voting explanation, yet the label the
    /// bridge reports for it is the *temporary companion* name, which is not
    /// contested and so cannot be told apart by inspecting the label. Without
    /// this gate the user would get a tile and a blocking screen for one
    /// operation.
    static func markHandedOff(username: String) {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UsernamePrefs.shared.inFlightRegistrationUsername = trimmed
        UsernamePrefs.shared.completedTileUsername = nil
        // Without this the tile would wait for the registration's next phase
        // change to notice the record, leaving Home showing the call to action
        // for an attempt that is already running.
        NotificationCenter.default.post(name: .DWUsernameRegistrationHandedOff, object: nil)
    }

    // MARK: - Actions

    /// The success tile's arrow, and its row. The caller opens the profile; the
    /// record is spent either way, so the tile does not come back.
    func acknowledgeSuccess() {
        prefs.completedTileUsername = nil
        apply(.hidden)
    }

    /// The X on a failed or interrupted tile. The user loses nothing: a
    /// Core-funded attempt's recovery lock is persisted SDK-side, and the
    /// create screen still surfaces it through `hasPendingRegistrationRecovery`
    /// on the next visit. Only this tile's claim on the Home slot is dropped,
    /// which lets the Join DashPay call to action return.
    func dismiss() {
        prefs.inFlightRegistrationUsername = nil
        prefs.completedTileUsername = nil
        apply(.hidden)
    }

    // MARK: - State

    private func reload() {
        let bridge = DWIdentityRegistrationBridge.shared
        let handedOff = prefs.inFlightRegistrationUsername

        // Only the registration this tile was handed (see `markHandedOff`).
        // Contested submissions and invitation claims travel the same bridge
        // but keep their own screen, and must not raise a second report here.
        if let username = bridge.currentUsername,
           !username.isEmpty,
           username == handedOff {
            if bridge.isCompleted {
                complete(username)
            } else if bridge.isFailed {
                apply(.failed(username: username, step: bridge.currentState))
            } else {
                apply(.inProgress(username: username, step: bridge.currentState))
            }
            return
        }

        restoreFromRecord()
    }

    private func complete(_ username: String) {
        prefs.inFlightRegistrationUsername = nil
        prefs.completedTileUsername = username
        apply(.success(username: username))
    }

    /// Nothing is running. Either a finished registration is still waiting to
    /// be acknowledged, or an attempt was recorded and never came back.
    private func restoreFromRecord() {
        if let completed = prefs.completedTileUsername, !completed.isEmpty {
            apply(.success(username: completed))
            return
        }

        guard let pending = prefs.inFlightRegistrationUsername, !pending.isEmpty else {
            apply(.hidden)
            return
        }

        // The attempt may well have landed while the app was dead — the
        // registration runs in the coordinator and the last leg is Platform's,
        // not ours. If an identity and name now resolve, report the success the
        // user never got to see.
        let identity = DWCurrentUserIdentityInfo.shared
        if identity.hasIdentity, let registered = identity.username, !registered.isEmpty {
            complete(registered)
            return
        }

        // Otherwise the honest answer is that we do not know how far it got:
        // the coordinator is `.idle` after a relaunch and there is no step to
        // claim. Resuming is the user's call — it re-enters the PIN gate, which
        // must never fire on its own at launch.
        apply(.interrupted(username: pending))
    }

    private func apply(_ newState: UsernameTileState) {
        guard newState != state else { return }
        state = newState
        onStateChange?()
    }
}

#endif

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

import Foundation

#if DASHPAY

/// What the Home tile is reporting about a DashPay username registration.
///
/// Only non-contested, non-invitation registrations reach these states — see
/// `UsernameRegistrationTileModel` for why the other two keep the blocking
/// create screen.
enum UsernameTileState: Equatable {
    case hidden
    /// Running right now; `step` is the bridge's current 1-of-3 stage.
    case inProgress(username: String, step: DWDPRegistrationState)
    /// Reached a terminal failure at `step`.
    case failed(username: String, step: DWDPRegistrationState)
    /// A registration was started and the app died before it finished. There
    /// is no live progress to report on relaunch, so the tile says exactly
    /// that rather than inventing a stage.
    case interrupted(username: String)
    case success(username: String)

    /// Whether the tile is holding the Home slot the Join DashPay banner would
    /// otherwise occupy. Read by `HomeViewModel.checkJoinDashPay()`.
    var occupiesHomeSlot: Bool {
        self != .hidden
    }

    var username: String? {
        switch self {
        case .hidden:
            return nil
        case .inProgress(let username, _),
             .failed(let username, _),
             .interrupted(let username),
             .success(let username):
            return username
        }
    }

    /// The legacy status object that owns every string and fraction the tile
    /// draws. Built rather than reimplemented: `DWDPRegistrationStatus` already
    /// carries the "(1/3) Processing Payment" copy in all 43 locales along with
    /// its failure variants, and its `progress` is the model the steps are
    /// defined by. `nil` where there is nothing for it to describe — the
    /// interrupted case has no equivalent there, which is the one line of copy
    /// the tile owns itself.
    var status: DWDPRegistrationStatus? {
        switch self {
        case .hidden, .interrupted:
            return nil
        case .inProgress(let username, let step):
            return DWDPRegistrationStatus(state: step, failed: false, username: username)
        case .failed(let username, let step):
            return DWDPRegistrationStatus(state: step, failed: true, username: username)
        case .success(let username):
            return DWDPRegistrationStatus(state: .done, failed: false, username: username)
        }
    }

    /// How full the bar is, or `nil` where no bar is drawn.
    ///
    /// A bar only appears while the registration is actually advancing: on a
    /// failure it would read as "still working", and after a kill there is no
    /// honest value to give it.
    var progress: Double? {
        guard case .inProgress = self, let status else { return nil }
        return Double(status.progress())
    }
}

#endif

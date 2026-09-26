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

/// One deep link the app accepted: a payment URL, a `dashwallet://` action
/// (scan, integration, request, DashConnect) or a DashPay invitation —
/// scheme or universal link.
@objc(DWDeepLink)
final class DeepLink: NSObject {
    @objc let url: URL
    /// Handled by the DashPay invitation flow instead of `DWURLParser`.
    @objc let isInvitation: Bool

    @objc(initWithURL:isInvitation:)
    init(url: URL, isInvitation: Bool) {
        self.url = url
        self.isInvitation = isInvitation
    }

    /// Classified by the invitation recognizer; without DashPay every link
    /// is a URL.
    @objc(initWithURL:)
    convenience init(url: URL) {
        #if DASHPAY
        self.init(url: url, isInvitation: DWInvitationLinkNormalizer.isInvitationURL(url))
        #else
        self.init(url: url, isInvitation: false)
        #endif
    }
}

/// The one place pending deep links live, and the one rule for when the next
/// one is handled.
///
/// Every entry point enqueues — `application:openURL:`, a universal link,
/// the deferred-launch replay, the initial controller's kept links, an
/// invitation that arrived on a walletless install — and every link stays
/// here, in arrival order, until the app can act on it: a wallet is
/// presented, the device is unlocked, no launch hold is pending, and no
/// earlier link is still presenting its screen. One link is handed over at a
/// time; the owner reports `dispatchDidFinish()` once that link's screen has
/// finished its transition, and asks again.
///
/// Walletless installs need no separate store: an invitation (or a URL)
/// that arrived before setup waits here and is handed over once setup has
/// presented the wallet. The wallet verdict itself belongs to the owner —
/// the queue only refuses to act while there is nothing to act on.
///
/// Pure: no UIKit, so ordering and gating are unit-tested.
@objc(DWDeepLinkQueue)
final class DeepLinkQueue: NSObject {
    @objc private(set) var pending: [DeepLink] = []
    /// A link was handed over and its screen has not reported back yet.
    @objc private(set) var isDispatching = false

    @objc var isEmpty: Bool { pending.isEmpty }

    @objc func enqueue(_ link: DeepLink) {
        pending.append(link)
    }

    /// The next link to hand over, or nil: nothing pending, one still in
    /// flight, or the app cannot act on links right now. A returned link is
    /// in flight until `dispatchDidFinish()`.
    @objc(takeNextWithWalletPresented:unlocked:launchHoldPending:)
    func takeNext(walletPresented: Bool, unlocked: Bool, launchHoldPending: Bool) -> DeepLink? {
        guard !isDispatching, walletPresented, unlocked, !launchHoldPending, !pending.isEmpty else {
            return nil
        }
        isDispatching = true
        return pending.removeFirst()
    }

    @objc func dispatchDidFinish() {
        isDispatching = false
    }
}

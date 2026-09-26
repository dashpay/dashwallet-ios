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
    /// A Dash URL the parser has no action for: its handling is one
    /// "Unsupported URL" alert, so a burst of them is shown once.
    @objc let isUnsupported: Bool

    @objc(initWithURL:isInvitation:isUnsupported:)
    init(url: URL, isInvitation: Bool, isUnsupported: Bool) {
        self.url = url
        self.isInvitation = isInvitation
        self.isUnsupported = isUnsupported
    }

    /// Classified by the invitation recognizer; without DashPay every link
    /// is a URL. `isUnsupported` is the owner's verdict from the URL parser.
    @objc(initWithURL:isUnsupported:)
    convenience init(url: URL, isUnsupported: Bool = false) {
        #if DASHPAY
        let isInvitation = DWInvitationLinkNormalizer.isInvitationURL(url)
        #else
        let isInvitation = false
        #endif
        self.init(url: url, isInvitation: isInvitation, isUnsupported: !isInvitation && isUnsupported)
    }
}

/// What `enqueue` did with a link.
@objc(DWDeepLinkAdmission)
enum DeepLinkAdmission: Int {
    case queued
    /// The same URL as the link queued just before it: dropped.
    case droppedDuplicate
    /// An unsupported URL while one is already pending: dropped, its
    /// alert is the pending one's.
    case droppedUnsupportedCoalesced
    /// Queued, and the oldest pending link was dropped to stay within
    /// `DeepLinkQueue.capacity`.
    case queuedEvictingOldest
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
/// time; the owner reports `dispatchDidFinish()` once that link's handler
/// has presented what it presents (or failed, or was cancelled), and asks
/// again.
///
/// An invitation is handed over only once the home screen can take one
/// (sync done); it waits in place without holding up the URLs behind it,
/// which have no such condition. Walletless installs need no separate
/// store either: an invitation (or a URL) that arrived before setup waits
/// here and is handed over once setup has presented the wallet. The wallet
/// verdict itself belongs to the owner — the queue only refuses to act
/// while there is nothing to act on.
///
/// Bounded: at most `capacity` links (a burst keeps the newest), a link
/// identical to the one queued just before it is dropped, and unsupported
/// URLs are shown as one alert per burst.
///
/// Pure: no UIKit, so ordering, gating and bounds are unit-tested.
@objc(DWDeepLinkQueue)
final class DeepLinkQueue: NSObject {
    @objc static let capacity = 10

    @objc private(set) var pending: [DeepLink] = []
    /// A link was handed over and its handler has not reported back yet.
    @objc private(set) var isDispatching = false

    @objc var isEmpty: Bool { pending.isEmpty }

    @objc(enqueue:)
    @discardableResult
    func enqueue(_ link: DeepLink) -> DeepLinkAdmission {
        if let last = pending.last, last.url == link.url {
            return .droppedDuplicate
        }
        if link.isUnsupported, pending.contains(where: { $0.isUnsupported }) {
            return .droppedUnsupportedCoalesced
        }
        pending.append(link)
        if pending.count > Self.capacity {
            pending.removeFirst()
            return .queuedEvictingOldest
        }
        return .queued
    }

    /// The next link to hand over, or nil: nothing pending that can be acted
    /// on, one still in flight, or the app cannot act on links right now. A
    /// returned link is in flight until `dispatchDidFinish()`.
    @objc(takeNextWithWalletPresented:unlocked:launchHoldPending:invitationsReady:)
    func takeNext(walletPresented: Bool, unlocked: Bool, launchHoldPending: Bool, invitationsReady: Bool) -> DeepLink? {
        guard !isDispatching, walletPresented, unlocked, !launchHoldPending else {
            return nil
        }
        guard let index = pending.firstIndex(where: { !$0.isInvitation || invitationsReady }) else {
            return nil
        }
        isDispatching = true
        return pending.remove(at: index)
    }

    @objc func dispatchDidFinish() {
        isDispatching = false
    }
}

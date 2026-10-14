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
    /// An unsupported URL while one is already pending or its alert is
    /// being shown: dropped, its alert is that one's.
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
    /// Identifies the hand-over in flight: a completion — or the owner's
    /// watchdog — finishes only the dispatch it belongs to, so a report
    /// that arrives after the queue moved on cannot finish a later link.
    @objc private(set) var dispatchToken = 0
    /// The unsupported link handed over and not finished yet: its alert is
    /// the burst's one alert, so unsupported links arriving while it is up
    /// are coalesced into it as if it were still pending.
    private var activeUnsupported: DeepLink?

    @objc var isEmpty: Bool { pending.isEmpty }

    @objc(enqueue:)
    @discardableResult
    func enqueue(_ link: DeepLink) -> DeepLinkAdmission {
        if let last = pending.last ?? activeUnsupported, last.url == link.url {
            return .droppedDuplicate
        }
        if link.isUnsupported, activeUnsupported != nil || pending.contains(where: { $0.isUnsupported }) {
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
    /// on, one still in flight, or the app cannot act on links right now —
    /// `attached` is the owner's presentation hierarchy being in a window,
    /// without which a handler's screen is presented from nowhere and its
    /// completion never comes. A returned link is in flight, under the new
    /// `dispatchToken`, until `dispatchDidFinish(token:)`.
    @objc(takeNextWithWalletPresented:attached:unlocked:launchHoldPending:invitationsReady:)
    func takeNext(walletPresented: Bool, attached: Bool, unlocked: Bool, launchHoldPending: Bool, invitationsReady: Bool) -> DeepLink? {
        guard let index = nextIndex(walletPresented: walletPresented, attached: attached, unlocked: unlocked,
                                    launchHoldPending: launchHoldPending, invitationsReady: invitationsReady) else {
            return nil
        }
        isDispatching = true
        dispatchToken &+= 1
        let link = pending.remove(at: index)
        activeUnsupported = link.isUnsupported ? link : nil
        return link
    }

    /// Whether `takeNext` with the same arguments would hand a link over,
    /// without taking it.
    @objc(hasNextWithWalletPresented:attached:unlocked:launchHoldPending:invitationsReady:)
    func hasNext(walletPresented: Bool, attached: Bool, unlocked: Bool, launchHoldPending: Bool, invitationsReady: Bool) -> Bool {
        nextIndex(walletPresented: walletPresented, attached: attached, unlocked: unlocked,
                  launchHoldPending: launchHoldPending, invitationsReady: invitationsReady) != nil
    }

    private func nextIndex(walletPresented: Bool, attached: Bool, unlocked: Bool, launchHoldPending: Bool,
                           invitationsReady: Bool) -> Int? {
        guard !isDispatching, walletPresented, attached, unlocked, !launchHoldPending else {
            return nil
        }
        return pending.firstIndex(where: { !$0.isInvitation || invitationsReady })
    }

    /// Ends the dispatch `token` belongs to; false — and nothing changes —
    /// when that dispatch is already over.
    @objc(dispatchDidFinishWithToken:)
    @discardableResult
    func dispatchDidFinish(token: Int) -> Bool {
        guard isDispatching, token == dispatchToken else { return false }
        isDispatching = false
        activeUnsupported = nil
        return true
    }

    /// Ends the dispatch in flight, whichever it is.
    @objc func dispatchDidFinish() {
        isDispatching = false
        activeUnsupported = nil
    }
}

/// Holds the next link's hand-over while a presentation is in transition.
///
/// A link settles at the tap that ends its screen — an alert's OK, a
/// dismissed DashConnect error — while that screen is still animating away,
/// and a handler presenting right then would present from a controller in
/// transition, which UIKit refuses or takes down with it. The gate waits for
/// that transition — its coordinator's completion, else a 0.1 s poll — and
/// asks the queue again. A sheet the user holds mid-drag holds the link
/// until it is let go. After `maxWaits` waits the link is handed over
/// regardless; a handler whose screen UIKit then refuses is left to the
/// queue's watchdog.
@objc(DWLinkHandOverGate)
final class LinkHandOverGate: NSObject {
    static let poll: TimeInterval = 0.1

    let maxWaits: Int
    private(set) var waits = 0
    private var retryScheduled = false

    /// About 10 s of polls.
    override convenience init() {
        self.init(maxWaits: 100)
    }

    init(maxWaits: Int) {
        self.maxWaits = maxWaits
    }

    /// True — and `retry` runs once the transition has ended — while
    /// something under `roots` is being presented, dismissed, pushed or
    /// popped; false when the link can be handed over now.
    @objc(deferHandOverFromRoots:retry:)
    func deferHandOver(from roots: [UIViewController], retry: @escaping () -> Void) -> Bool {
        deferHandOver(from: roots as [PresentationNode], retry: retry)
    }

    func deferHandOver(from roots: [PresentationNode], retry: @escaping () -> Void) -> Bool {
        guard let node = PresentationOwner.nodeInTransition(from: roots) else {
            reset()
            return false
        }
        guard waits < maxWaits else {
            DWLogger.log("LINKS a presentation is still in transition after \(waits) waits; handing the next link over")
            reset()
            return false
        }
        guard !retryScheduled else { return true }
        retryScheduled = true
        waits += 1
        var fired = false
        let fire = { [weak self] in
            guard !fired else { return }
            fired = true
            self?.retryScheduled = false
            retry()
        }
        let queued = (node as? UIViewController)?.transitionCoordinator?.animate(alongsideTransition: nil) { _ in
            DispatchQueue.main.async(execute: fire)
        } ?? false
        if !queued {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.poll, execute: fire)
        }
        return true
    }

    /// Starts the count afresh: called whenever there is nothing to hand
    /// over, so a later transition gets the whole wait.
    @objc func reset() {
        waits = 0
    }
}

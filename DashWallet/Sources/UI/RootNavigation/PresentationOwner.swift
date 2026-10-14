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

import UIKit

/// The little of a view controller the presentation-owner walk needs, so
/// the walk is a pure function over any tree and unit-tested without a
/// window.
protocol PresentationNode: AnyObject {
    /// What this node — or one of its ancestors — presents.
    var presentedNode: PresentationNode? { get }
    /// The node that actually presents this one (nil when not presented).
    var presentingNode: PresentationNode? { get }
    /// The child that is on screen: a tab's selected controller, a
    /// navigation stack's top; nil for a leaf.
    var activeChildNode: PresentationNode? { get }
    /// Whether this node is still being presented or dismissed.
    var isInTransition: Bool { get }
    /// Whether this node is in any animated transition: presented or
    /// dismissed, or a container pushing, popping or switching children.
    var isAnimatingTransition: Bool { get }
}

extension PresentationNode {
    var isAnimatingTransition: Bool { isInTransition }
}

/// Finds who owns the presentation over the active hierarchy, so a deep
/// link's handler can dismiss it — and everything presented above it —
/// before presenting its own screen.
///
/// `presentedViewController` reads a presentation an ancestor owns, but not
/// one a descendant owns: a screen that defines its presentation context
/// (the amount step) presents on its own, and the container above it sees
/// nothing. The walk goes down the active chain — tab → selected → top of
/// stack — and returns the deepest node whose presented controller names it
/// as presenter; when nothing on the chain owns one but something is
/// presented above it (an ancestor of the root owns it), the root itself,
/// whose `dismiss` forwards to that ancestor; nil when nothing is presented.
enum PresentationOwner {
    static func find(from root: PresentationNode) -> PresentationNode? {
        var chain: [PresentationNode] = [root]
        var node = root
        while let child = node.activeChildNode, !chain.contains(where: { $0 === child }) {
            chain.append(child)
            node = child
        }
        for candidate in chain.reversed() {
            if let presented = candidate.presentedNode, presented.presentingNode === candidate {
                return candidate
            }
        }
        return root.presentedNode != nil ? root : nil
    }

    /// What a deep link's handler does before presenting its own screen.
    enum Step {
        /// Nothing is presented: go ahead.
        case none
        /// The presentation over `owner` is still animating in or out; UIKit
        /// refuses a dismissal until that transition ends, so wait for it.
        case wait(PresentationNode)
        /// Dismiss what `owner` presents, then go ahead.
        case dismiss(PresentationNode)
    }

    static func step(from root: PresentationNode) -> Step {
        guard let owner = find(from: root) else { return .none }
        if owner.presentedNode?.isInTransition == true {
            return .wait(owner)
        }
        return .dismiss(owner)
    }
}

extension PresentationOwner {
    /// The first node reachable from `roots` — down the active chains and
    /// through every presentation over them — that is in an animated
    /// transition, or nil when nothing is.
    static func nodeInTransition(from roots: [PresentationNode]) -> PresentationNode? {
        var visited: [PresentationNode] = []
        var pending = roots
        while let node = pending.popLast() {
            guard !visited.contains(where: { $0 === node }) else { continue }
            visited.append(node)
            if node.isAnimatingTransition { return node }
            if let presented = node.presentedNode { pending.append(presented) }
            if let child = node.activeChildNode { pending.append(child) }
        }
        return nil
    }
}

extension UIViewController: PresentationNode {
    var presentedNode: PresentationNode? { presentedViewController }
    var presentingNode: PresentationNode? { presentingViewController }
    var activeChildNode: PresentationNode? {
        if let tab = self as? UITabBarController { return tab.selectedViewController }
        if let navigation = self as? UINavigationController { return navigation.topViewController }
        return nil
    }
    var isInTransition: Bool { isBeingPresented || isBeingDismissed }
    var isAnimatingTransition: Bool { isInTransition || transitionCoordinator != nil }
}

/// Holds the next link's hand-over while anything on screen is in
/// transition.
///
/// A link settles at the tap that ends its screen — an alert's OK, a
/// dismissed DashConnect error — while that screen is still animating away,
/// and a handler presenting right then would present from a controller in
/// transition, which UIKit refuses or takes down with it. The gate asks
/// again every 0.1 s until nothing under the roots is presented, dismissed,
/// pushed or popped and the root container is not swapping children. A
/// sheet the user holds mid-drag holds the link until it is let go. A link
/// held for `maxHold` is handed over regardless; a handler whose screen
/// UIKit then refuses is left to the queue's watchdog.
@objc(DWLinkHandOverGate)
final class LinkHandOverGate: NSObject {
    static let poll: TimeInterval = 0.1

    let maxHold: TimeInterval
    private let now: () -> Date
    private(set) var holdingSince: Date?
    private var retryScheduled = false

    override convenience init() {
        self.init(maxHold: 10)
    }

    init(maxHold: TimeInterval, now: @escaping () -> Date = Date.init) {
        self.maxHold = maxHold
        self.now = now
    }

    /// True — and `retry` runs `poll` later — while something under
    /// `roots` is in transition or `rootTransitioning`; false when the link
    /// can be handed over now.
    @objc(deferHandOverFromRoots:rootTransitioning:retry:)
    func deferHandOver(from roots: [UIViewController], rootTransitioning: Bool, retry: @escaping () -> Void) -> Bool {
        deferHandOver(from: roots as [PresentationNode], rootTransitioning: rootTransitioning, retry: retry)
    }

    func deferHandOver(from roots: [PresentationNode], rootTransitioning: Bool = false,
                       retry: @escaping () -> Void) -> Bool {
        guard rootTransitioning || PresentationOwner.nodeInTransition(from: roots) != nil else {
            reset()
            return false
        }
        let since: Date
        if let holdingSince {
            since = holdingSince
        } else {
            since = now()
            holdingSince = since
            DWLogger.log("LINKS holding the next link: a screen is in transition")
        }
        guard now().timeIntervalSince(since) < maxHold else {
            DWLogger.log("LINKS a screen is still in transition after \(Int(maxHold)) s; handing the next link over")
            reset()
            return false
        }
        guard !retryScheduled else { return true }
        retryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.poll) { [weak self] in
            self?.retryScheduled = false
            retry()
        }
        return true
    }

    /// Ends the current hold: called whenever there is nothing to hand
    /// over, so a later transition is held for the whole `maxHold`.
    @objc func reset() {
        holdingSince = nil
    }
}

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

extension UIViewController: PresentationNode {
    var presentedNode: PresentationNode? { presentedViewController }
    var presentingNode: PresentationNode? { presentingViewController }
    var activeChildNode: PresentationNode? {
        if let tab = self as? UITabBarController { return tab.selectedViewController }
        if let navigation = self as? UINavigationController { return navigation.topViewController }
        return nil
    }
    var isInTransition: Bool { isBeingPresented || isBeingDismissed }
}

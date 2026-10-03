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

import XCTest

#if canImport(dashpay)
@testable import dashpay
#elseif canImport(dashwallet)
@testable import dashwallet
#else
#error("Unknown test host module")
#endif

/// A view-controller-like node: `presented` is visible from the owner and
/// every ancestor of it (as `presentedViewController` is), `presenter` names
/// the owner.
private final class Node: PresentationNode {
    let name: String
    var child: Node?
    var parent: Node?
    private var owned: Node?
    var presenter: Node?

    init(_ name: String, child: Node? = nil) {
        self.name = name
        self.child = child
        child?.parent = self
    }

    func present(_ node: Node) {
        owned = node
        node.presenter = self
    }

    func dismiss() {
        owned?.presenter = nil
        owned = nil
    }

    var presentedNode: PresentationNode? {
        var node: Node? = self
        while let current = node {
            if let owned = current.owned { return owned }
            node = current.parent
        }
        return nil
    }

    var presentingNode: PresentationNode? { presenter }
    var activeChildNode: PresentationNode? { child }
    var isInTransition = false
}

/// `PresentationOwner.find` returns the controller whose `dismiss` takes the
/// whole presented chain down before the next deep link presents.
final class PresentationOwnerTests: XCTestCase {
    private func hierarchy() -> (root: Node, tab: Node, navigation: Node, home: Node) {
        let home = Node("home")
        let navigation = Node("navigation", child: home)
        let tab = Node("tab", child: navigation)
        let root = Node("root", child: tab)
        return (root, tab, navigation, home)
    }

    func testNothingPresentedIsNoOwner() {
        let (_, tab, _, _) = hierarchy()
        XCTAssertNil(PresentationOwner.find(from: tab))
    }

    /// The invitation alert and the payment confirmation are presented with
    /// a default style: UIKit hands them to the root-most presenter, which
    /// is an ancestor of the tab. The tab sees the presentation through its
    /// ancestor, owns nothing itself, and is the one to dismiss through.
    func testAPresentationOwnedAboveTheChainIsDismissedThroughTheChainsRoot() {
        let (root, tab, _, home) = hierarchy()
        let alert = Node("alert")
        root.present(alert)
        XCTAssertNotNil(home.presentedNode, "a descendant sees an ancestor's presentation")
        XCTAssertTrue(PresentationOwner.find(from: tab) === tab)
        XCTAssertTrue(PresentationOwner.find(from: root) === root)
    }

    /// The amount step defines its own presentation context: a confirmation
    /// presented over it is owned by the amount step, and the tab's own
    /// `presentedViewController` is nil. The walk finds the amount step.
    func testAPresentationOwnedByADescendantIsFoundAtThatDescendant() {
        let (_, tab, navigation, home) = hierarchy()
        let amount = Node("amount")
        navigation.child = amount
        amount.parent = navigation
        let confirmation = Node("confirmation")
        amount.present(confirmation)
        XCTAssertNil(tab.presentedNode, "the tab does not see a descendant's presentation")
        XCTAssertTrue(PresentationOwner.find(from: tab) === amount)
        _ = home
    }

    /// Home presenting on its own (a context-defining screen) is found
    /// before the navigation stack or the tab.
    func testTheDeepestOwnerWins() {
        let (root, tab, _, home) = hierarchy()
        let modal = Node("modal")
        home.present(modal)
        let ancestorSheet = Node("sheet")
        root.present(ancestorSheet)
        XCTAssertTrue(PresentationOwner.find(from: tab) === home)
        home.dismiss()
        XCTAssertTrue(PresentationOwner.find(from: tab) === tab, "then only the ancestor's presentation remains")
    }

    // MARK: Step

    func testNothingPresentedStepsStraightOn() {
        let (_, tab, _, _) = hierarchy()
        guard case .none = PresentationOwner.step(from: tab) else { return XCTFail("expected .none") }
    }

    /// A sheet still animating in is not dismissed — UIKit refuses that —
    /// but waited for; once on screen it is dismissed at its owner.
    func testAPresentationInTransitionIsWaitedForThenDismissed() {
        let (root, tab, _, _) = hierarchy()
        let sheet = Node("sheet")
        root.present(sheet)
        sheet.isInTransition = true
        guard case let .wait(waiting) = PresentationOwner.step(from: tab) else { return XCTFail("expected .wait") }
        XCTAssertTrue(waiting === tab)

        sheet.isInTransition = false
        guard case let .dismiss(owner) = PresentationOwner.step(from: tab) else { return XCTFail("expected .dismiss") }
        XCTAssertTrue(owner === tab)
    }

    /// The wait is decided at the owner the walk finds: a descendant whose
    /// presentation is still animating is waited for there.
    func testADescendantsPresentationInTransitionIsWaitedForAtTheDescendant() {
        let (_, tab, _, home) = hierarchy()
        let modal = Node("modal")
        home.present(modal)
        modal.isInTransition = true
        guard case let .wait(waiting) = PresentationOwner.step(from: tab) else { return XCTFail("expected .wait") }
        XCTAssertTrue(waiting === home)
    }

    func testACycleInTheActiveChainDoesNotLoop() {
        let (_, tab, navigation, _) = hierarchy()
        navigation.child = tab
        XCTAssertNil(PresentationOwner.find(from: tab))
    }
}

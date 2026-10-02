//  
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

import SwiftUI

extension View {
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        Group {
            if condition {
                transform(self)
            } else {
                self
            }
        }
    }
}

extension View {
    /// Closes the ways out of a screen that the screen's own Back button does
    /// not cover — the navigation edge swipe and a sheet's swipe-down — while
    /// `locked`, for a payment that is waiting on the network. The screen
    /// disables its own Back button.
    func lockingExit(_ locked: Bool) -> some View {
        background(ExitLockView(locked: locked))
            // A SwiftUI-presented sheet keeps its own dismissal preference.
            .interactiveDismissDisabled(locked)
    }
}

/// One hold on the ways out of a screen: its navigation stack's edge swipe and
/// its presented root's swipe-down. Holds are counted per stack and per root,
/// so independent owners (`lockingExit`, `PaymentController`) can overlap: the
/// first hold saves the original value, the last release restores it.
@MainActor
final class ExitHold {
    private final class Count {
        var holds = 0
        var original = false
    }

    private static let navigationCounts = NSMapTable<UINavigationController, Count>.weakToStrongObjects()
    private static let presentationCounts = NSMapTable<UIViewController, Count>.weakToStrongObjects()

    private weak var navigation: UINavigationController?
    private weak var presentedRoot: UIViewController?

    init(on controller: UIViewController) {
        if let navigationController = controller.navigationController {
            let count = Self.count(for: navigationController, in: Self.navigationCounts)
            if count.holds == 0 {
                count.original = navigationController.interactivePopGestureRecognizer?.isEnabled ?? true
                navigationController.interactivePopGestureRecognizer?.isEnabled = false
            }
            count.holds += 1
            navigation = navigationController
        }
        var root = controller
        while let parent = root.parent { root = parent }
        if root.presentingViewController != nil {
            let count = Self.count(for: root, in: Self.presentationCounts)
            if count.holds == 0 {
                count.original = root.isModalInPresentation
                root.isModalInPresentation = true
            }
            count.holds += 1
            presentedRoot = root
        }
    }

    /// Idempotent.
    func release() {
        if let navigationController = navigation,
           let count = Self.navigationCounts.object(forKey: navigationController) {
            count.holds -= 1
            if count.holds == 0 {
                navigationController.interactivePopGestureRecognizer?.isEnabled = count.original
                Self.navigationCounts.removeObject(forKey: navigationController)
            }
        }
        if let root = presentedRoot, let count = Self.presentationCounts.object(forKey: root) {
            count.holds -= 1
            if count.holds == 0 {
                root.isModalInPresentation = count.original
                Self.presentationCounts.removeObject(forKey: root)
            }
        }
        navigation = nil
        presentedRoot = nil
    }

    private static func count<Key: AnyObject>(for key: Key, in table: NSMapTable<Key, Count>) -> Count {
        if let count = table.object(forKey: key) { return count }
        let count = Count()
        table.setObject(count, forKey: key)
        return count
    }
}

private struct ExitLockView: UIViewControllerRepresentable {
    let locked: Bool

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.locked = locked
    }

    final class Controller: UIViewController {
        var locked = false {
            didSet { if locked != oldValue { apply() } }
        }

        private var hold: ExitHold?

        override func loadView() {
            // Behind the screen's content; it must not take its taps.
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        deinit {
            // Torn down while still locked, without a viewWillDisappear.
            let hold = hold
            Task { @MainActor in hold?.release() }
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            // Back from another tab or a cover while still locked.
            apply()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            // The stack's gesture is shared; never hold it for a screen that
            // is no longer showing.
            hold?.release()
            hold = nil
        }

        private func apply() {
            if locked, hold == nil, parent != nil {
                hold = ExitHold(on: self)
            } else if !locked {
                hold?.release()
                hold = nil
            }
        }
    }
}

extension Font {
    var pointSize: CGFloat {
        return self.uiFont.pointSize
    }
    
    var uiFont: UIFont {
        switch self {
        case .largeTitle:
            return UIFont.preferredFont(forTextStyle: .largeTitle)
        case .title:
            return UIFont.preferredFont(forTextStyle: .title1)
        case .title2:
            return UIFont.preferredFont(forTextStyle: .title2)
        case .title3:
            return UIFont.preferredFont(forTextStyle: .title3)
        case .headline:
            return UIFont.preferredFont(forTextStyle: .headline)
        case .subheadline:
            return UIFont.preferredFont(forTextStyle: .subheadline)
        case .body:
            return UIFont.preferredFont(forTextStyle: .body)
        case .callout:
            return UIFont.preferredFont(forTextStyle: .callout)
        case .footnote:
            return UIFont.preferredFont(forTextStyle: .footnote)
        case .caption:
            return UIFont.preferredFont(forTextStyle: .caption1)
        case .caption2:
            return UIFont.preferredFont(forTextStyle: .caption2)
        default:
            return UIFont.systemFont(ofSize: UIFont.systemFontSize)
        }
    }
}

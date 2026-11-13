//
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

import DashUIKit
import SwiftUI
import UIKit

/// The leading control of an Explore screen's DashUIKit bar.
enum ExploreNavigationBarLeading {
    case back
    case close
}

extension UIViewController {
    /// Hosts DashUIKit's `NavigationBar` at the top of this UIKit screen, under
    /// the status bar, for a screen that hides the system bar. Returns the
    /// hosting controller so content can sit below the bar.
    @discardableResult
    func installExploreNavigationBar(
        title: String,
        leading: ExploreNavigationBarLeading,
        onBack: @escaping () -> Void,
        onInfo: (() -> Void)?
    ) -> UIHostingController<AnyView> {
        // One colour for the status-bar fill and the bar, so the top edge reads
        // as a single band in both themes.
        let barColor = UIColor(named: "SecondaryBackgroundColor") ?? .systemBackground
        let navBar = ExploreNavigationBar(title: title, leading: leading, background: Color(barColor),
                                          onBack: onBack, onInfo: onInfo)

        let topFillView = UIView()
        topFillView.translatesAutoresizingMaskIntoConstraints = false
        topFillView.backgroundColor = barColor
        view.addSubview(topFillView)

        let host = UIHostingController(rootView: AnyView(navBar))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)

        NSLayoutConstraint.activate([
            topFillView.topAnchor.constraint(equalTo: view.topAnchor),
            topFillView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topFillView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topFillView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),

            host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        return host
    }
}

// MARK: - ExploreNavigationBar

private struct ExploreNavigationBar: View {
    /// The bar's 20pt edge padding, a 34pt circle and the 10pt minimum gap.
    private static let titleInset: CGFloat = 20 + 34 + 10

    let title: String
    let leading: ExploreNavigationBarLeading
    let background: Color
    let onBack: () -> Void
    let onInfo: (() -> Void)?

    var body: some View {
        DashUIKit.NavigationBar(
            leading: {
                switch leading {
                case .back: DashUIKit.NavigationBarElement.back.button(action: onBack)
                case .close: DashUIKit.NavigationBarElement.close.button(action: onBack)
                }
            },
            central: {
                Text(title)
                    .font(.subheadMedium)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    // The bar centres the title over the full width; keep a long
                    // merchant name clear of the circles on both sides.
                    // TODO(dashuikit-title-inset): drop once NavigationBar reserves this itself.
                    .padding(.horizontal, Self.titleInset)
            },
            trailing: {
                if let onInfo {
                    DashUIKit.NavigationBarElement.info.button(action: onInfo)
                }
            }
        )
        .background(background)
    }
}

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
import DashUIKit
import UIKit

struct ToastView: View {
    var text: String
    var icon: IconName? = nil
    var actionText: String? = nil
    var action: (() -> Void)? = nil
    var closeButtonIcon: IconName? = nil
    var closeAction: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 0) {
            if let icon = icon {
                VStack {
                    Icon(name: icon)
                        // `font` sizes SF Symbols only. A `.custom` asset is
                        // resizable with no intrinsic cap, so without this
                        // frame it grows to fill the row and squeezes the
                        // text onto two lines.
                        .font(.system(size: 15))
                        .frame(maxHeight: 20)
                        .padding(.leading, 8)
                        .padding(.top, 12)
                    Spacer()
                }
            }
            
            Text(text)
                .font(.system(size: 14))
                .lineSpacing(3)
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            
            if (actionText != nil && action != nil) || (closeButtonIcon != nil && closeAction != nil) {
                Spacer()
            }
            
            if let text = actionText, let action = action {
                DashButton(text: text, style: .plain, size: .extraSmall, stretch: false, action: action)
                    .overrideForegroundColor(Color.dash.primaryBackground)
            }
            
            if let icon = closeButtonIcon, let action = closeAction {
                DashButton(leadingIcon: icon, style: .plain, size: .small, stretch: false, action: action)
                    .overrideForegroundColor(Color.dash.primaryBackground)
            }
        }
        .padding(.horizontal, 8)
        .foregroundColor(Color.dash.primaryBackground)
        .background(Color.dash.primaryText.opacity(0.9))
        .cornerRadius(10)
    }
}

class ToastHostingView: UIView {
    private var hostingController: UIHostingController<ToastView>?
    
    init(text: String,
         icon: IconName? = nil,
         actionText: String? = nil,
         action: (() -> Void)? = nil,
         closeButtonIcon: IconName? = nil,
         closeAction: (() -> Void)? = nil
    ) {
        super.init(frame: .zero)
        
        let toastView = ToastView(
            text: text,
            icon: icon,
            actionText: actionText,
            action: action,
            closeButtonIcon: closeButtonIcon,
            closeAction: closeAction
        )
        hostingController = UIHostingController(rootView: toastView)
        
        guard let hostingView = hostingController?.view else { return }
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.backgroundColor = UIColor.clear
        addSubview(hostingView)
        
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension UIViewController {
    func showToast(
        text: String,
        icon: IconName? = nil,
        duration: TimeInterval? = nil,
        actionText: String? = nil,
        action: ((ToastHostingView) -> Void)? = nil,
        closeButtonIcon: IconName? = nil,
        closeAction: ((ToastHostingView) -> Void)? = nil
    ) {
        var toastView: ToastHostingView!
        let actionClosure: () -> Void = { action?(toastView) }
        let closeActionClosure: () -> Void = { closeAction?(toastView) }
            
        toastView = ToastHostingView(
            text: text,
            icon: icon,
            actionText: actionText,
            action: actionClosure,
            closeButtonIcon: closeButtonIcon,
            closeAction: closeActionClosure
        )
        
        toastView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toastView)
        
        NSLayoutConstraint.activate([
            toastView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 10).withPriority(.defaultHigh),
            view.trailingAnchor.constraint(greaterThanOrEqualTo: toastView.trailingAnchor, constant: 10).withPriority(.defaultHigh),
            toastView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -20),
            toastView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        ])
        
        toastView.alpha = 0.0
        UIView.animate(withDuration: 0.5, animations: {
            toastView.alpha = 1.0
        }) { _ in
            if let duration = duration {
                UIView.animate(withDuration: 0.5, delay: duration, options: .curveEaseOut, animations: {
                    toastView.alpha = 0.0
                }) { _ in
                    toastView.removeFromSuperview()
                }
            }
        }
    }
    
    func hideToast(toastView: ToastHostingView) {
        UIView.animate(withDuration: 0.5, delay: 0.0, options: .curveEaseOut, animations: {
            toastView.alpha = 0.0
        }) { _ in
            toastView.removeFromSuperview()
        }
    }
}

extension UIViewController {
    /// Bottom-anchored **DashUIKit** toast hosted from a UIKit screen.
    ///
    /// Distinct from `showToast` above, which renders the app-local `ToastView`.
    /// `DashUIKit.Toast` sizes its own icon (16x16 in a 24x24 slot) and resolves
    /// it from the DashUIKit bundle, where the toast imagesets live — so UIKit
    /// screens that must match the SwiftUI design-system call sites
    /// (`dexOfflineToast`, `SelectCoinView`) use this one. Geometry matches
    /// them: bottom overlay, 20pt sides, 16pt above the safe area. The toast
    /// auto-dismisses, so it carries no close button.
    ///
    /// Hosted on the outermost controller of the caller's own hierarchy, not on
    /// `view`: a screen presented as a `UIViewControllerRepresentable` inside a
    /// `DashUIKit.BottomSheet` has a view that ends where the sheet's content
    /// ends, and a toast pinned to it lands mid-screen instead of at the bottom
    /// edge the other toasts share.
    ///
    /// The hosting controller is parented to that same controller. Adding a
    /// child's view to a hierarchy its parent does not own — the window, say —
    /// trips UIKit's `_associatedViewControllerForwardsAppearanceCallbacks`
    /// check and raises.
    func presentDashUIKitToast(style: ToastStyle,
                               message: String,
                               duration: TimeInterval = 3.5) {
        var owner: UIViewController = self
        while let parent = owner.parent { owner = parent }

        let host = UIHostingController(rootView: DashUIKit.Toast(style: style, message: message))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        owner.addChild(host)
        owner.view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: owner.view.leadingAnchor, constant: 20),
            host.view.trailingAnchor.constraint(equalTo: owner.view.trailingAnchor, constant: -20),
            host.view.bottomAnchor.constraint(equalTo: owner.view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
        host.didMove(toParent: owner)

        host.view.alpha = 0
        UIView.animate(withDuration: 0.3) { host.view.alpha = 1 }
        UIView.animate(withDuration: 0.3, delay: duration, options: .curveEaseOut) {
            host.view.alpha = 0
        } completion: { _ in
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
        }
    }
}

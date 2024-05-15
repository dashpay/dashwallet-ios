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
                Icon(name: icon)
                    .font(.system(size: 15))
                    .padding(.leading, 8)
            }
            
            Text(text)
                .font(.system(size: 13))
                .padding(.leading, 8)
            Spacer()
            
            if let text = actionText, let action = action {
                DashButton(text: text, action: action, style: .plain, size: .small)
                    .overrideForegroundColor(Color.background)
            }
            
            if let icon = closeButtonIcon, let action = closeAction {
                DashButton(leadingIcon: icon, action: action, style: .plain, size: .small)
                    .overrideForegroundColor(Color.background)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .foregroundColor(Color.background)
        .background(Color.primaryText.opacity(0.9))
        .cornerRadius(10)
    }
}

class ToastHostingView: UIView {
    private var hostingController: UIHostingController<ToastView>?
    
    init(message: String) {
        super.init(frame: .zero)
        
        let toastView = ToastView(text: message)
        hostingController = UIHostingController(rootView: toastView)
        
        guard let hostingView = hostingController?.view else { return }
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        layer.cornerRadius = 10
        layer.masksToBounds = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension UIViewController {
    func showToast(message: String) {
        let toastView = ToastHostingView(message: message)
        toastView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(toastView)
        
        NSLayoutConstraint.activate([
            toastView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            toastView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            toastView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
        
        toastView.alpha = 0.0
        UIView.animate(withDuration: 0.5, animations: {
            toastView.alpha = 1.0
        }) { _ in
            UIView.animate(withDuration: 0.5, delay: 2.0, options: .curveEaseOut, animations: {
                toastView.alpha = 0.0
            }) { _ in
                toastView.removeFromSuperview()
            }
        }
    }
}

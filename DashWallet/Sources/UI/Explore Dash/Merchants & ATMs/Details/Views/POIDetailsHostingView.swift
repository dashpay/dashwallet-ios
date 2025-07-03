//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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
import SwiftUI

// MARK: - POIDetailsHostingView

/// UIKit wrapper for the SwiftUI PointOfUseDetailsView
@MainActor
class POIDetailsHostingView: UIView {
    
    // Action handlers
    public var payWithDashHandler: (() -> Void)?
    public var sellDashHandler: (() -> Void)?
    public var dashSpendAuthHandler: ((GiftCardProvider) -> Void)?
    public var buyGiftCardHandler: ((GiftCardProvider) -> Void)?
    public var showAllLocationsActionBlock: (() -> Void)?
    
    private let merchant: ExplorePointOfUse
    private let isShowAllHidden: Bool
    private var hostingController: UIHostingController<POIDetailsView>?
    
    init(merchant: ExplorePointOfUse, isShowAllHidden: Bool = false) {
        self.merchant = merchant
        self.isShowAllHidden = isShowAllHidden
        super.init(frame: .zero)
        setupHostingController()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupHostingController() {
        var swiftUIView = POIDetailsView(merchant: merchant, isShowAllHidden: isShowAllHidden)
        
        // Pass through the action handlers
        swiftUIView.payWithDashHandler = { [weak self] in
            self?.payWithDashHandler?()
        }
        swiftUIView.sellDashHandler = { [weak self] in
            self?.sellDashHandler?()
        }
        swiftUIView.dashSpendAuthHandler = { [weak self] provider in
            self?.dashSpendAuthHandler?(provider)
        }
        swiftUIView.buyGiftCardHandler = { [weak self] provider in
            self?.buyGiftCardHandler?(provider)
        }
        swiftUIView.showAllLocationsActionBlock = { [weak self] in
            self?.showAllLocationsActionBlock?()
        }
        
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(hostingController.view)
        
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        self.hostingController = hostingController
    }
}

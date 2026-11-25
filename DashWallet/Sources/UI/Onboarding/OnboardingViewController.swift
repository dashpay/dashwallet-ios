//
//  Created by Dash Core Group
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

import SwiftUI
import UIKit

@objc(DWOnboardingViewControllerDelegate)
protocol OnboardingViewControllerDelegate: AnyObject {
    func onboardingViewControllerDidFinish(_ controller: OnboardingViewController)
}

/// The onboarding carousel for `DWInitialViewController`: the photo, the
/// UIKit mini wallet over it, and `OnboardingView` on top.
///
/// The mini wallet is a UIKit child here, not a SwiftUI representable: the
/// demo app inside it would otherwise inherit the carousel's SwiftUI
/// environment and lay out differently from the real app.
@objc(DWOnboardingViewController)
final class OnboardingViewController: UIViewController {
    @objc weak var delegate: OnboardingViewControllerDelegate?

    private let viewModel = OnboardingViewModel()
    private let demoController = OnboardingDemoViewController()

    @objc
    static func controller() -> OnboardingViewController {
        OnboardingViewController()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        let background = UIImageView(image: UIImage(named: "image_bg"))
        background.contentMode = .scaleAspectFill
        background.clipsToBounds = true
        background.isAccessibilityElement = false
        embedFullScreen(background)

        demoController.onInteractionChange = { [weak self] in self?.viewModel.isInteractive = $0 }
        demoController.view.accessibilityElementsHidden = true
        addChild(demoController)
        embedFullScreen(demoController.view)
        demoController.didMove(toParent: self)

        viewModel.onPageChange = { [weak self] in self?.demoController.show(page: $0) }
        viewModel.onFinish = { [weak self] in
            guard let self else { return }
            self.delegate?.onboardingViewControllerDidFinish(self)
        }

        let hosting = UIHostingController(rootView: OnboardingView(viewModel: viewModel))
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        embedFullScreen(hosting.view)
        hosting.didMove(toParent: self)
    }

    private func embedFullScreen(_ subview: UIView) {
        view.addSubview(subview)
        subview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            subview.topAnchor.constraint(equalTo: view.topAnchor),
            subview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            subview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

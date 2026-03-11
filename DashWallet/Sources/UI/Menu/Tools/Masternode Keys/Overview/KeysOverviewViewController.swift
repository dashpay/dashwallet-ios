//
//  Created by PT
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

// MARK: - KeysOverviewViewController

@objc(DWKeysOverviewViewController)
final class KeysOverviewViewController: BaseViewController {
    private var navigationContainer: UIView!
    private var backButtonBorder: UIView!
    private var backButtonIcon: UIImageView!

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateBackButtonAppearance()
        }
    }
}

extension KeysOverviewViewController {
    private func configureHierarchy() {
        view.backgroundColor = .dw_secondaryBackground()

        configureCustomNavigationBar()
        addSwiftUIContent()
    }

    private func addSwiftUIContent() {
        let swiftUIView = KeysOverviewContentView(navigationController: navigationController)

        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: navigationContainer.bottomAnchor, constant: 10),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureCustomNavigationBar() {
        navigationContainer = UIView()
        navigationContainer.translatesAutoresizingMaskIntoConstraints = false
        navigationContainer.backgroundColor = .dw_secondaryBackground()
        view.addSubview(navigationContainer)

        NSLayoutConstraint.activate([
            navigationContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            navigationContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationContainer.heightAnchor.constraint(equalToConstant: 64)
        ])

        let backButton = UIButton(type: .custom)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(backButtonTapped), for: .touchUpInside)
        navigationContainer.addSubview(backButton)

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: navigationContainer.leadingAnchor, constant: 20),
            backButton.centerYAnchor.constraint(equalTo: navigationContainer.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        backButtonBorder = UIView()
        backButtonBorder.translatesAutoresizingMaskIntoConstraints = false
        backButtonBorder.layer.cornerRadius = 17
        backButtonBorder.layer.borderWidth = 1.5
        backButtonBorder.isUserInteractionEnabled = false
        backButton.addSubview(backButtonBorder)

        NSLayoutConstraint.activate([
            backButtonBorder.centerXAnchor.constraint(equalTo: backButton.centerXAnchor),
            backButtonBorder.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            backButtonBorder.widthAnchor.constraint(equalToConstant: 34),
            backButtonBorder.heightAnchor.constraint(equalToConstant: 34)
        ])

        backButtonIcon = UIImageView()
        backButtonIcon.translatesAutoresizingMaskIntoConstraints = false
        backButtonIcon.contentMode = .scaleAspectFit
        backButton.addSubview(backButtonIcon)

        NSLayoutConstraint.activate([
            backButtonIcon.centerXAnchor.constraint(equalTo: backButton.centerXAnchor, constant: -1),
            backButtonIcon.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            backButtonIcon.heightAnchor.constraint(equalToConstant: 12)
        ])

        updateBackButtonAppearance()
    }

    private func updateBackButtonAppearance() {
        if let borderColor = UIColor(named: "Gray300Alpha30") {
            backButtonBorder.layer.borderColor = borderColor.cgColor
        } else {
            backButtonBorder.layer.borderColor = UIColor.dw_gray300().withAlphaComponent(0.3).cgColor
        }

        let iconName = traitCollection.userInterfaceStyle == .dark ? "controls-back-dark-mode" : "controls-back"
        backButtonIcon.image = UIImage(named: iconName)
        backButtonIcon.tintColor = .dw_label()
    }

    @objc private func backButtonTapped() {
        navigationController?.popViewController(animated: true)
    }
}

// MARK: NavigationBarStyleable

extension KeysOverviewViewController: NavigationBarStyleable {
    var prefersLargeTitles: Bool { false }
    var largeTitleDisplayMode: UINavigationItem.LargeTitleDisplayMode { .never }
}

// MARK: NavigationBarDisplayable

extension KeysOverviewViewController: NavigationBarDisplayable {
    var isNavigationBarHidden: Bool { true }
}

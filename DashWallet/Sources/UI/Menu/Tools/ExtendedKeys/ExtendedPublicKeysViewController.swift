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

// MARK: - ExtendedPublicKeysViewController

@objc(DWExtendedPublicKeysViewController)
final class ExtendedPublicKeysViewController: BaseViewController {
    private let model: ExtendedPublicKeysModel

    private var navigationContainer: UIView!
    private var backButtonBorder: UIView!
    private var backButtonIcon: UIImageView!

    init() {
        model = ExtendedPublicKeysModel()

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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

extension ExtendedPublicKeysViewController {
    private func configureHierarchy() {
        view.backgroundColor = .dw_secondaryBackground()

        configureCustomNavigationBar()

        // Add SwiftUI content with title
        addSwiftUIContent()
    }

    private func addSwiftUIContent() {
        // SwiftUI view with title and content
        let swiftUIView = ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(NSLocalizedString("Extended public keys", comment: ""))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color(uiColor: .dw_label()))
                    .padding(.horizontal, 20)

                KeysVStackView(items: model.derivationPaths.map { $0.item })
                    .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(uiColor: .dw_secondaryBackground()))

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
        // Create navigation container (64px height)
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

        // Create back button (44x44 touch area)
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

        // Create circular border (34x34)
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

        // Create chevron icon (12px height)
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
        // Update border color
        if let borderColor = UIColor(named: "Gray300Alpha30") {
            backButtonBorder.layer.borderColor = borderColor.cgColor
        } else {
            backButtonBorder.layer.borderColor = UIColor.dw_gray300().withAlphaComponent(0.3).cgColor
        }

        // Update icon based on appearance
        let iconName = traitCollection.userInterfaceStyle == .dark ? "controls-back-dark-mode" : "controls-back"
        backButtonIcon.image = UIImage(named: iconName)
        backButtonIcon.tintColor = .dw_label()
    }

    @objc private func backButtonTapped() {
        navigationController?.popViewController(animated: true)
    }

}

// MARK: NavigationBarStyleable

extension ExtendedPublicKeysViewController: NavigationBarStyleable {
    var prefersLargeTitles: Bool { false }
    var largeTitleDisplayMode: UINavigationItem.LargeTitleDisplayMode { .never }
}

// MARK: NavigationBarDisplayable

extension ExtendedPublicKeysViewController: NavigationBarDisplayable {
    var isNavigationBarHidden: Bool { true }
}

// MARK: - SwiftUI VStack Implementation for Comparison

struct KeysVStackView: View {
    let items: [DerivationPathKeysItem]
    @State private var copiedItemIndex: Int? = nil

    var body: some View {
        VStack(spacing: kMenuVGap) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                KeyItemRow(
                    item: item,
                    showCopiedMessage: copiedItemIndex == index,
                    onCopy: {
                        copiedItemIndex = index
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            if copiedItemIndex == index {
                                copiedItemIndex = nil
                            }
                        }
                    }
                )
            }
        }
        .padding(kMenuPadding)
        .background(Color(uiColor: .dw_background()))
        .cornerRadius(kMenuRadius)
    }
}

struct KeyItemRow: View {
    let item: DerivationPathKeysItem
    let showCopiedMessage: Bool
    let onCopy: () -> Void

    var body: some View {
        Button(action: {
            // Copy to clipboard
            UIPasteboard.general.string = item.value
            onCopy()
        }) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    // Title: caption1 font (12pt Regular)
                    Text(item.title)
                        .font(.caption1)
                        .foregroundColor(Color(uiColor: .dw_secondaryText()))

                    // Key value: footnote font (13pt Regular)
                    Text(item.value)
                        .font(.footnote)
                        .foregroundColor(Color(uiColor: .dw_label()))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Copy icon (40x40 wrapper with 13.6px icon centered)
                ZStack {
                    Color.clear
                        .frame(width: 40, height: 40)

                    Image(uiImage: UIImage(named: "icon_copy_outline")!)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 13.6)
                        .foregroundColor(Color(uiColor: .dw_label()))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(uiColor: .dw_background()))
            .cornerRadius(14)
            .contentShape(Rectangle()) // Make entire area tappable
        }
        .buttonStyle(PlainButtonStyle()) // Remove default button styling
        .overlay(
            Group {
                if showCopiedMessage {
                    Text("Copied")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
        )
    }
}

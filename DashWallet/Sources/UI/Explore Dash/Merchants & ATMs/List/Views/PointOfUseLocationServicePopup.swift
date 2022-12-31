//
//  Created by Pavel Tikhonenko
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

class PointOfUseLocationServicePopup: UIView {
    var continueBlock: (() -> ())?

    private var title: String
    private var details: String

    init(title: String, details: String) {
        self.title = title
        self.details = details
        super.init(frame: .zero)

        configureHierarchy()
    }


    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func continueButtonAction() {
        continueBlock?()
        removeFromSuperview()
    }

    func configureHierarchy() {
        backgroundColor = UIColor.black.withAlphaComponent(0.2)

        let container = UIView(frame: .zero)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .dw_background()
        container.layer.cornerRadius = 14.0
        container.layer.masksToBounds = true
        addSubview(container)

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.alignment = .center
        stackView.spacing = 15
        stackView.axis = .vertical
        stackView.distribution = .fill
        container.addSubview(stackView)

        let iconView = UIImageView(image: UIImage(systemName: "location.fill"))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.layer.cornerRadius = 25.0
        iconView.layer.masksToBounds = true
        iconView.backgroundColor = UIColor.dw_dashBlue().withAlphaComponent(0.2)
        iconView.contentMode = .center
        iconView.tintColor = .dw_dashBlue()
        stackView.addArrangedSubview(iconView)

        let textStackView = UIStackView()
        textStackView.translatesAutoresizingMaskIntoConstraints = false
        textStackView.alignment = .center
        textStackView.spacing = 5
        textStackView.axis = .vertical
        textStackView.distribution = .fill
        stackView.addArrangedSubview(textStackView)

        var label = UILabel(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .dw_font(forTextStyle: UIFont.TextStyle.body)
        label.text = title
        textStackView.addArrangedSubview(label)

        label = UILabel(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textColor = .dw_secondaryText()
        label.textAlignment = .center
        label.font = UIFont.dw_font(forTextStyle: UIFont.TextStyle.footnote)
        label.text = details
        textStackView.addArrangedSubview(label)
        let continueButton = DWActionButton()
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        continueButton.setTitle(NSLocalizedString("Continue", comment: ""), for: .normal)
        continueButton.addTarget(self, action: #selector(continueButtonAction), for: .touchUpInside)
        stackView.addArrangedSubview(continueButton)
        NSLayoutConstraint.activate([
            container.centerYAnchor.constraint(equalTo: centerYAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor,
                                               constant: 15),
            container.trailingAnchor.constraint(equalTo: trailingAnchor,
                                                constant: -15),
            stackView.topAnchor.constraint(equalTo: container.topAnchor,
                                           constant: 20),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor,
                                              constant: -20),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                               constant: 20),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor,
                                                constant: -20),
            iconView.widthAnchor.constraint(equalToConstant: 50.0),
            iconView.heightAnchor.constraint(equalToConstant: 50.0),
            continueButton.heightAnchor.constraint(equalToConstant: 40.0),
            continueButton.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            continueButton.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
        ])
    }

    func show(in view: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(self)

        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: view.topAnchor),
            bottomAnchor.constraint(equalTo: view.bottomAnchor),
            leadingAnchor.constraint(equalTo: view.leadingAnchor),
            trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    static func show(in view: UIView, title: String, details: String, completion: @escaping () -> Void) {
        let popup = PointOfUseLocationServicePopup(title: title, details: details)
        popup.continueBlock = completion
        popup.show(in: view.window!)
    }
}

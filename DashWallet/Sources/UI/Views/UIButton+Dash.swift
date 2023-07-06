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

extension UIButton.Configuration {
    public static func image(asset: UIImage) -> UIButton.Configuration {
        var background = UIButton.Configuration.plain().background
        background.image = asset

        var style = UIButton.Configuration.plain()
        style.background = background
        return style
    }

    public static func plain(title: String, font: UIFont) -> UIButton.Configuration {
        configuration(from: .plain(), with: title, and: font)
    }

    public static func tinted(title: String, font: UIFont) -> UIButton.Configuration {
        var configuration = configuration(from: .tinted(), with: title, and: font)

        var background = configuration.background
        background.backgroundColor = UIColor.dw_dashBlue().withAlphaComponent(0.08)

        var attributedTitle = configuration.attributedTitle
        attributedTitle?.foregroundColor = configuration.baseForegroundColor

        configuration.background = background
        configuration.baseForegroundColor = .dw_dashBlue()
        configuration.attributedTitle = attributedTitle

        return configuration
    }

    public static func configuration(from configuration: UIButton.Configuration, with title: String, and font: UIFont) -> UIButton.Configuration {
        var style = configuration

        var background = style.background
        background.cornerRadius = 6

        var attributes = AttributeContainer()
        attributes.foregroundColor = style.baseForegroundColor
        attributes.font = font

        style.title = title
        style.background = background
        style.attributedTitle = AttributedString(title, attributes: attributes)
        return style
    }
}

// MARK: - TintedButton

final class TintedButton: DashButton {
    override func initializeConfiguration(with title: String, and font: UIFont?) {
        var configuration = UIButton.Configuration.tinted(title: title,
                                                          font: font ?? .dw_font(forTextStyle: .body))
        self.configuration = configuration
    }
}

// MARK: - ImageButton

final class ImageButton: UIButton {
    init(image: UIImage) {
        super.init(frame: .zero)
        configuration = .image(asset: image)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - DashButton

class DashButton: UIButton {
    init(title: String, font: UIFont? = nil) {
        super.init(frame: .zero)

        initializeConfiguration(with: title, and: font)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    internal func initializeConfiguration(with title: String, and font: UIFont?) {
        var configuration = UIButton.Configuration.plain(title: title,
                                                         font: font ?? .dw_font(forTextStyle: .body))
        self.configuration = configuration
    }
}

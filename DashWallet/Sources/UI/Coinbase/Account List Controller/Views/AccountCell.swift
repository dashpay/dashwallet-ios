//
//  Created by tkhp
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

final class AccountCell: UITableViewCell {
    @IBOutlet var containerStackView: UIStackView!
    @IBOutlet var checkboxButton: UIButton!

    private var sourceView: SourceView!

    public func update(with item: SourceViewDataProvider?) {
        sourceView.update(with: item, isBalanceHidden: false)
    }

    private func configureHierarchy() {
        sourceView = SourceView(frame: .zero)
        sourceView.translatesAutoresizingMaskIntoConstraints = false
        containerStackView.insertArrangedSubview(sourceView, at: 0)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        checkboxButton.isSelected = selected
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        backgroundColor = .dw_secondaryBackground()
        contentView.backgroundColor = .dw_secondaryBackground()

        configureHierarchy()
    }
}

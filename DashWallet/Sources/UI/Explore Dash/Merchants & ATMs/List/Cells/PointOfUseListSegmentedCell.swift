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

class PointOfUseListSegmentedCell: UITableViewCell {

    var segmentDidChangeBlock: ((Int) -> Void)?
    var segmentTitles: [String] = []
    var selectedIndex = Int.max

    var segmentedControl: UISegmentedControl!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(with items: [String], selectedIndex: Int) {
        if self.selectedIndex == selectedIndex { return }

        self.selectedIndex = selectedIndex
        segmentTitles = items
        segmentedControl.removeAllSegments()

        for (i, item) in items.enumerated() {
            segmentedControl.insertSegment(withTitle: item, at: i, animated: false)
        }

        segmentedControl.selectedSegmentIndex = selectedIndex
    }

    @objc
    func segmentedControlAction() {
        segmentDidChangeBlock?(segmentedControl.selectedSegmentIndex)
    }

    private func configureHierarchy() {
        segmentedControl = UISegmentedControl()
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.addTarget(self, action: #selector(segmentedControlAction), for: .valueChanged)
        segmentedControl.selectedSegmentIndex = 0
        contentView.addSubview(segmentedControl)

        NSLayoutConstraint.activate([
            segmentedControl.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            segmentedControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }


}

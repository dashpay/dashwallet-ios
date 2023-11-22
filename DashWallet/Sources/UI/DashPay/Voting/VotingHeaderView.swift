//  
//  Created by Andrei Ashikhmin
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

import Foundation

class VotingHeaderView: UIView {
    var filterButtonHandler: (() -> ())?
    
    @IBOutlet private var subtitleLabel: UILabel!
    @IBOutlet private var filterLabel: UILabel!
    @IBOutlet private var amountLabel: UILabel!
    @IBOutlet private var filterButton: UIButton!
    @IBOutlet private var searchBar: UISearchBar!
    
    @IBAction
    private func onFilterButtonTap() {
        filterButtonHandler?()
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        configureLayout()
    }
    
    func set(filterLabel: String) {
        self.filterLabel.text = filterLabel
    }
    
    func set(duplicateAmount: Int) {
        self.amountLabel.text = String.localizedStringWithFormat(NSLocalizedString("%ld duplicates", comment: "Voting"), duplicateAmount)
    }
    
    func set(searchQuerytChangedHandler: UISearchBarDelegate) {
        searchBar.delegate = searchQuerytChangedHandler
    }
    
    private func configureLayout() {
        subtitleLabel.text = NSLocalizedString("As a masternode owner you can vote to approve requested usernames before users will be able to create it.", comment: "Voting")
        searchBar.placeholder = NSLocalizedString("Search by username", comment: "Voting")
        searchBar.searchTextField.font = .dw_regularFont(ofSize: 15)
        filterLabel.text = VotingFilters.defaultFilters.filterBy?.localizedString ?? ""

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.dw_mediumFont(ofSize: 13),
            .foregroundColor: UIColor.dw_dashBlue()
        ]
        let attributedTitle = NSAttributedString(string: NSLocalizedString("Filter", comment: ""), attributes: attributes)
        filterButton.setAttributedTitle(attributedTitle, for: .normal)
    }
}

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

import Foundation
import UIKit
 
private let kSearchDebounceDelay: TimeInterval = 0.4

protocol PointOfUseListSearchCellDelegate: AnyObject {
    func searchCell(_ cell: PointOfUseListSearchCell, shouldStartSearchWith query: String)
    func searchCellDidEndSearching(searchCell: PointOfUseListSearchCell)
}

class PointOfUseListSearchCell: UITableViewCell {
    var searchBar: UISearchBar!
    weak var delegate: PointOfUseListSearchCellDelegate?
    private var didTapDeleteButton: Bool = false
    private var query: String?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureHierarchy()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func resetSearchBar() {
        searchBar.text = ""
    }
    
    func configureHierarchy() {
        self.searchBar = UISearchBar()
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        contentView.addSubview(searchBar)
        
        NSLayoutConstraint.activate([
            searchBar.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            searchBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 9),
            searchBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -9),
        ])
    }
    
}

extension PointOfUseListSearchCell: UISearchBarDelegate {
    @objc func performSearch() {
        if let q = self.query {
            delegate?.searchCell(self, shouldStartSearchWith: q)
        }
    }
    
    func search(with query: String) {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(performSearch), object: nil)
    
        self.query = query
        
        self.perform(#selector(performSearch), with: nil, afterDelay: kSearchDebounceDelay)
    }
    
    func searchBar(_ searchBar: UISearchBar, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        didTapDeleteButton = text.isEmpty
        return true
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if !didTapDeleteButton && searchText.isEmpty {
            searchBar.resignFirstResponder()
            query = nil
            delegate?.searchCellDidEndSearching(searchCell: self)
            return
        }
        
        didTapDeleteButton = false
        search(with: searchText)
    }
}

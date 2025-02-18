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

// MARK: - VotingFilters

struct VotingFilters: Equatable {

    enum SortBy {
        case dateAsc
        case datesDesc
        case votesDesc
        case votesAsc
        
        var localizedString: String {
            switch self {
            case .dateAsc:
                return NSLocalizedString("Old to new", comment: "Voting")
            case .datesDesc:
                return NSLocalizedString("New to old", comment: "Voting")
            case .votesDesc:
                return NSLocalizedString("High to low", comment: "Voting")
            case .votesAsc:
                return NSLocalizedString("Low to high", comment: "Voting")
            }
        }
    }
    
    enum FilterBy {
        case all
        case approved
        case notVoted
        case hasBlockVotes
        
        var localizedString: String {
            switch self {
            case .all:
                return NSLocalizedString("All", comment: "Voting")
            case .approved:
                return NSLocalizedString("I have approved", comment: "Voting")
            case .notVoted:
                return NSLocalizedString("I have not voted", comment: "Voting")
            case .hasBlockVotes:
                return NSLocalizedString("Has blocked votes", comment: "Voting")
            }
        }
    }

    var sortBy: SortBy?
    var filterBy: FilterBy?
    var onlyDuplicates: Bool?
    var onlyWithLinks: Bool?

    static let defaultFilters = VotingFilters(sortBy: .datesDesc, filterBy: .notVoted, onlyDuplicates: true, onlyWithLinks: false)
    
    var localizedDescription: String? {
        var string: [String] = []

        if let value = sortBy {
            string.append(value.localizedString)
        }

        if onlyDuplicates == true {
            string.append(NSLocalizedString("Only duplicates", comment: "Voting"))
        }
        
        if onlyWithLinks == true {
            string.append(NSLocalizedString("Only with links", comment: "Voting"))
        }

        return string.isEmpty ? nil : string.joined(separator: ", ")
    }
}

extension VotingFilters {
    var items: Set<VotingFilterItem> {
        var set: Set<VotingFilterItem> = []

        if let value = sortBy {
            switch value {
            case .dateAsc:
                set.insert(.dateAsc)
            case .datesDesc:
                set.insert(.dateDesc)
            case .votesDesc:
                set.insert(.votesDesc)
            case .votesAsc:
                set.insert(.votesAsc)
            }
        }

        if let value = filterBy {
            switch value {
            case .all:
                set.insert(.typeAll)
            case .approved:
                set.insert(.typeApproved)
            case .notVoted:
                set.insert(.typeNotVoted)
            case .hasBlockVotes:
                set.insert(.typeHasBlockVotes)
            }
        }
        
        if onlyDuplicates == true {
            set.insert(.onlyDuplicates)
        }
        
        if onlyWithLinks == true {
            set.insert(.onlyRequestsWithLinks)
        }
        
        return set
    }
}

// MARK: - VotingFilterItem

enum VotingFilterItem: String {
    case dateAsc
    case dateDesc
    case votesAsc
    case votesDesc
    case typeAll
    case typeApproved
    case typeNotVoted
    case typeHasBlockVotes
    case onlyDuplicates
    case onlyRequestsWithLinks
    case reset

    var itemsToUnselect: [VotingFilterItem] {
        switch self {
        case .dateAsc:
            return [.dateDesc, .votesAsc, .votesDesc]
        case .dateDesc:
            return [.dateAsc, .votesAsc, .votesDesc]
        case .votesAsc:
            return [.dateDesc, .dateAsc, .votesDesc]
        case .votesDesc:
            return [.dateAsc, .dateDesc, .votesAsc]
        case .typeAll:
            return [.typeApproved, .typeNotVoted, .typeHasBlockVotes]
        case .typeApproved:
            return [.typeAll, .typeNotVoted, .typeHasBlockVotes]
        case .typeNotVoted:
            return [.typeApproved, .typeAll, .typeHasBlockVotes]
        case .typeHasBlockVotes:
            return [.typeApproved, .typeAll, .typeNotVoted]
        default:
            return []
        }
    }

    var cellIdentifier: String {
        switch self {
        case .reset: 
            return "FilterItemResetCell"
        case .onlyRequestsWithLinks, .onlyDuplicates:
            return "VotingFilterItemCheckmarkCell"
        default:
            return "VotingFilterItemSelectableCell"
        }
    }

    var title: String {
        switch self {
        case .dateAsc:
            return NSLocalizedString("Date: Old to new", comment: "Voting")
        case .dateDesc:
            return NSLocalizedString("Date: New to old", comment: "Voting")
        case .votesAsc:
            return NSLocalizedString("Votes: Low to high", comment: "Voting")
        case .votesDesc:
            return NSLocalizedString("Votes: High to low", comment: "Voting")
        case .typeAll:
            return NSLocalizedString("All", comment: "Voting")
        case .typeApproved:
            return NSLocalizedString("I have approved", comment: "Voting")
        case .typeNotVoted:
            return NSLocalizedString("I have not voted", comment: "Voting")
        case .typeHasBlockVotes:
            return NSLocalizedString("Has blocked votes", comment: "Voting")
        case .reset:
            return NSLocalizedString("Reset Filters", comment: "")
        case .onlyDuplicates:
            return NSLocalizedString("Only duplicates", comment: "")
        case .onlyRequestsWithLinks:
            return NSLocalizedString("Only requests with links", comment: "")
        }
    }
}

// MARK: - VotingFiltersModel

final class VotingFiltersModel {
    var selected: Set<VotingFilterItem> = []
    var initialFilters: Set<VotingFilterItem>!

    var canApply: Bool {
        selected != initialFilters
    }

    var canReset: Bool {
        selected != VotingFilters.defaultFilters.items || canApply
    }

    func isFilterSelected(_ filter: VotingFilterItem) -> Bool {
        selected.contains(filter)
    }
    
    func onlySelf(_ filter: VotingFilterItem) -> Bool {
        filter == .onlyDuplicates || filter == .onlyRequestsWithLinks
    }

    func toggle(filter: VotingFilterItem) -> Bool {
        if isFilterSelected(filter) {
            if onlySelf(filter) || !filter.itemsToUnselect.filter({ isFilterSelected($0) }).isEmpty {
                selected.remove(filter)
                return true
            }
        } else {
            unselect(filters: filter.itemsToUnselect)
            selected.insert(filter)
            return true
        }

        return false
    }

    func unselect(filters: [VotingFilterItem]) {
        for item in filters {
            selected.remove(item)
        }
    }
    
    func resetFilters() {
        selected = VotingFilters.defaultFilters.items
    }
}

// MARK: VotingFiltersModel
extension VotingFiltersModel {
    var appliedFilters: VotingFilters {
        var filters = VotingFilters()

        if selected.contains(.dateAsc) {
            filters.sortBy = .dateAsc
        }

        if selected.contains(.dateDesc) {
            filters.sortBy = .datesDesc
        }

        if selected.contains(.votesAsc) {
            filters.sortBy = .votesAsc
        }
        
        if selected.contains(.votesDesc) {
            filters.sortBy = .votesDesc
        }
        
        if selected.contains(.typeAll) {
            filters.filterBy = .all
        }
        
        if selected.contains(.typeApproved) {
            filters.filterBy = .approved
        }
        
        if selected.contains(.typeNotVoted) {
            filters.filterBy = .notVoted
        }
        
        if selected.contains(.typeHasBlockVotes) {
            filters.filterBy = .hasBlockVotes
        }
        
        if selected.contains(.onlyDuplicates) {
            filters.onlyDuplicates = true
        }
        
        if selected.contains(.onlyRequestsWithLinks) {
            filters.onlyWithLinks = true
        }

        return filters
    }
}

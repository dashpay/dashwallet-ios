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

import Combine

enum VoteAction {
    case none
    case approved
    case revoked
    case blocked
    case unblocked
}

class VotingViewModel {
    private let prefs = VotingPrefs.shared
    private var nameCount = 1
    private var dao: UsernameRequestsDAO = UsernameRequestsDAOImpl.shared
    private var cancellableBag = Set<AnyCancellable>()
    private var groupedRequests: [GroupedUsernames] = []
    private var validKeys: [String] = [ // TODO: temp
        "kn2GwaSZkoY8qg6i2dPCpDtDoBCftJWMzZXtHDDJ1w7PjFYfq",
        "n6YtJ7pdDYPTa57imEHEp8zinq1oNGUdwZQdnGk1MMpCWBHEq",
        "maEiRZeKXNLZovNqoS3HkmZJGmACbro7s3eC8GenExLF7QMQs"
    ]
    
    private(set) var filters = VotingFilters.defaultFilters
    @Published private(set) var masternodeKeys: [MasternodeKey] = []
    @Published private(set) var filteredRequests: [GroupedUsernames] = []
    @Published var searchQuery: String = ""
    @Published var lastVoteAction: VoteAction = .none
    var selectedRequest: UsernameRequest? = nil
    
    public static let shared: VotingViewModel = .init()
    
    var shouldShowFirstTimeInfo: Bool {
        get { return !prefs.votingInfoShown }
        set { prefs.votingInfoShown = !newValue }
    }
    
    init() {
        $searchQuery
            .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
            .removeDuplicates()
            .sink { [weak self] text in
                self?.performSearch(text: text)
            }
            .store(in: &cancellableBag)
    }
    
    func apply(filters: VotingFilters) {
        self.filters = filters
        refresh()
    }
    
    func addMasternodeKey(key: String) -> Bool {
        if validKeys.contains(key) {
            masternodeKeys.append(MasternodeKey(key: key, ip: "182.151.12.\(masternodeKeys.count)"))
            return true
        }
        
        return false
    }
    
    func refresh() {
        Task {
            let requests: [UsernameRequest]
            
            if filters.onlyDuplicates ?? false {
                requests = await dao.duplicates(onlyWithLinks: filters.onlyWithLinks ?? false)
            } else {
                requests = await dao.all(onlyWithLinks: filters.onlyWithLinks ?? false)
            }
            
            let oldVotes = Dictionary(uniqueKeysWithValues: self.groupedRequests.map { ($0.username, $0.votesForUsername) })
            self.groupedRequests = Dictionary(grouping: requests, by: { $0.username })
                .map { username, reqs in 
                    var group = GroupedUsernames(username: username, requests: reqs.sortAndFilter(by: filters))
                    group.votesForUsername = max(oldVotes[username] ?? 0, 0)
                    return group
                }
                .filter { !$0.requests.isEmpty }
                .sorted { $0.username < $1.username }
            self.filteredRequests = self.groupedRequests.filter { $0.username.starts(with: searchQuery) }
        }
    }
}

// MARK: - Search

extension VotingViewModel {
    private func performSearch(text: String) {
        self.filteredRequests = self.groupedRequests.filter { $0.username.starts(with: searchQuery) }
    }
}

// MARK: - Sorting and filtering

extension [UsernameRequest] {
    func sortAndFilter(by filters: VotingFilters) -> [UsernameRequest] {
        let sortByOption = filters.sortBy
        let sorted: [UsernameRequest]
        
        switch sortByOption {
        case .dateAsc:
            sorted = self.sorted { $0.createdAt < $1.createdAt }
        case .datesDesc:
            sorted = self.sorted { $0.createdAt > $1.createdAt }
        case .votesAsc:
            sorted = self.sorted { $0.votes < $1.votes }
        case .votesDesc:
            sorted = self.sorted { $0.votes > $1.votes }
        default:
            sorted = self
        }
        
        let filterOption = filters.filterBy
        let result: [UsernameRequest]
        
        switch filterOption {
        case .approved:
            result = sorted.filter { $0.isApproved }
        case .notApproved:
            result = sorted.filter { !$0.isApproved }
        default:
            result = sorted
        }
        
        return result
    }
}

// MARK: - Voting

extension VotingViewModel {
    func vote(for requestId: String) {
        Task {
            if var copy = await dao.get(byRequestId: requestId) {
                copy.votes += masternodeKeys.count
                copy.isApproved = true
                await dao.update(dto: copy)
                lastVoteAction = .approved
                refresh()
                
                // TODO: MOCK_DASHPAY user own name approval. Remove when not needed
                if UsernamePrefs.shared.requestedUsernameId == requestId {
                    DWGlobalOptions.sharedInstance().dashpayUsername = copy.username
                }
                
                // TODO: MOCK_DASHPAY "votes left" check. Replace with actual logic
                if let groupIndex = groupedRequests.firstIndex(where: { group in
                    group.requests.contains { request in
                        request.requestId == requestId
                    }
                }) {
                    groupedRequests[groupIndex].votesForUsername += masternodeKeys.count
                }
            }
        }
    }
    
    func revokeVote(of requestId: String) {
        Task {
            if var copy = await dao.get(byRequestId: requestId) {
                copy.votes = max(copy.votes - masternodeKeys.count, 0)
                copy.isApproved = false
                await dao.update(dto: copy)
                lastVoteAction = .revoked
                refresh()
                
                // TODO: MOCK_DASHPAY user own name approval. Remove when not needed
                if UsernamePrefs.shared.requestedUsernameId == requestId {
                    DWGlobalOptions.sharedInstance().dashpayUsername = nil
                }
                
                // TODO: MOCK_DASHPAY "votes left" check. Replace with actual logic
                if let groupIndex = groupedRequests.firstIndex(where: { group in
                    group.requests.contains { request in
                        request.requestId == requestId
                    }
                }) {
                    groupedRequests[groupIndex].votesForUsername -= max(copy.votes - masternodeKeys.count, 0)
                }
            }
        }
    }
    
    func votesLeft(for requestId: String) -> Int {
        // TODO: MOCK_DASHPAY "votes left" check. Replace with actual logic
        let group = groupedRequests.first(where: { group in
            group.requests.contains { request in
                request.requestId == requestId
            }
        })
        return max(VotingConstants.maxVotes - (group?.votesForUsername ?? 0), 0)
    }
    
    func block(request requestId: String) {
        Task {
            if var copy = await dao.get(byRequestId: requestId) {
                copy.blockVotes += masternodeKeys.count
                await dao.update(dto: copy)
                lastVoteAction = .blocked
                refresh()
                
                // TODO: MOCK_DASHPAY user own name approval. Remove when not needed
                if UsernamePrefs.shared.requestedUsernameId == requestId {
                    DWGlobalOptions.sharedInstance().dashpayUsername = nil
                }
            }
        }
    }
    
    func unblock(request requestId: String) {
        Task {
            if var copy = await dao.get(byRequestId: requestId) {
                copy.blockVotes = max(copy.blockVotes - masternodeKeys.count, 0)
                await dao.update(dto: copy)
                lastVoteAction = .unblocked
                refresh()
            }
        }
    }
    
    func voteForAllFirstSubmitted() {
        Task {
            let submittedFirst = filteredRequests.compactMap { group in
                group.requests
                    .sorted { $0.createdAt < $1.createdAt }
                    .first?.requestId
            }
            await dao.vote(for: submittedFirst, voteIncrement: masternodeKeys.count)
            lastVoteAction = .approved
            refresh()
        }
    }
    
    func onVoteActionHandled() {
        lastVoteAction = .none
    }
}


// TODO: MOCK_DASHPAY remove when not needed

extension VotingViewModel {
    func addMockRequest() {
        Task {
            nameCount += 1
            let now = Date().timeIntervalSince1970
            let from: TimeInterval = 1658290321
            let randomValue = Double.random(in: from..<now)
            let identityData = withUnsafeBytes(of: UUID().uuid) { Data($0) }
            let names = ["John", "Doe", "Sarah", "Jane", "Jack", "Jill", "Bob"]
            let identity = (identityData as NSData).base58String()
            let randomName = names[Int.random(in: 0..<min(names.count, nameCount))]
            let link = nameCount % 2 == 0 ? "https://example.com" : nil
            let isApproved = false
            
            let dto = UsernameRequest(requestId: UUID().uuidString, username: randomName, createdAt: Int64(randomValue), identity: "\(identity)\(identity)\(identity)", link: link, votes: Int.random(in: 0..<15), blockVotes: Int.random(in: 0..<15), isApproved: isApproved)
            print(dto)
            await dao.create(dto: dto)
            
            refresh()
        }
    }
}

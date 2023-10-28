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

class VotingViewModel {
    private let prefs = VotingPrefs.shared
    private var nameCount = 1
    private var dao: UsernameRequestsDAO = UsernameRequestsDAOImpl.shared
    private var fullData: Dictionary<String, [UsernameRequest]> = [:]
    
    public static let shared: VotingViewModel = .init()
    public var duplicates: [String] = []
    
    var shouldShowFirstTimeInfo: Bool {
        get { return !prefs.infoShown }
        set { prefs.infoShown = !newValue }
    }
    
    init() {
        refresh()
    }
    
    func getAllRequests(for username: String) -> [UsernameRequest] {
        return fullData[username] ?? []
    }
    
    func addMockRequest() {
        nameCount += 1
        let now = Date().timeIntervalSince1970
        let from: TimeInterval = 1658290321
        let randomValue = Double.random(in: from..<now)
        let identityData = withUnsafeBytes(of: UUID().uuid) { Data($0) }
        let names = ["John", "Doe", "Sarah", "Jane", "Jack", "Jill", "Bob"]
        let identity = (identityData as NSData).base58String()
        let randomName = names[Int.random(in: 0..<min(names.count, nameCount))]
        let link = nameCount % 2 == 0 ? "https://example.com" : nil
        let isApproved = Bool.random()
        
        dao.create(dto: UsernameRequest(requestId: UUID().uuidString, username: randomName, createdAt: Int64(randomValue), identity: identity, link: link, votes: Int.random(in: 0..<15), isApproved: isApproved))
        
        refresh()
    }
    
    private func refresh() {
        let requests = dao.all()
        fullData = Dictionary(grouping: requests) { $0.username }
        duplicates = fullData.keys.sorted()
    }
}

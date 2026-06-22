//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

import SwiftUI
import UIKit
import StoreKit

@MainActor
final class AboutDashViewModel: ObservableObject {

    @Published private(set) var appVersion: String = ""
    @Published private(set) var dashSyncVersion: String = ""
    @Published private(set) var exploreStatus: String = ""
    @Published private(set) var lastDeviceSync: String = ""
    @Published private(set) var lastDeviceUpdate: String = ""

    let repositoryURL = "https://github.com/dashpay/dashwallet-ios"

    private var databaseObserver: NSObjectProtocol?

    private static let syncDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let updateDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    init() {
        // Touching `ExploreDash.shared` boots Firebase Storage, which throws an
        // NSException inside SwiftUI previews. Short-circuit to sample data there.
        guard !Self.isRunningInPreview else {
            applyPreviewData()
            return
        }

        appVersion = Self.makeAppVersion()
        dashSyncVersion = Self.makeDashSyncVersion()
        reloadExploreState()

        databaseObserver = NotificationCenter.default.addObserver(
            forName: ExploreDatabaseSyncManager.databaseHasBeenUpdatedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadExploreState()
            }
        }
    }

    deinit {
        if let databaseObserver {
            NotificationCenter.default.removeObserver(databaseObserver)
        }
    }

    // MARK: - Actions

    func reviewApp() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            return
        }
        SKStoreReviewController.requestReview(in: scene)
    }

    // MARK: - Explore Dash state

    private func reloadExploreState() {
        let explore = ExploreDash.shared

        switch explore.syncState {
        case .inititialing, .fetchingInfo:
            exploreStatus = NSLocalizedString("Fetching Info", comment: "Explore Dash")
        case .syncing:
            exploreStatus = NSLocalizedString("Syncing...", comment: "Explore Dash")
        case .synced:
            exploreStatus = NSLocalizedString("Synced", comment: "Explore Dash")
        case .error:
            exploreStatus = NSLocalizedString("Sync failed", comment: "Explore Dash")
        }

        if let syncDate = explore.lastSyncTryDate ?? explore.lastFailedSyncDate {
            lastDeviceSync = Self.syncDateFormatter.string(from: syncDate)
        } else {
            lastDeviceSync = "-"
        }

        lastDeviceUpdate = Self.updateDateFormatter.string(from: explore.lastServerUpdateDate)
    }

    // MARK: - Version strings

    private static func makeAppVersion() -> String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
        let buildVersion = info?["CFBundleVersion"] as? String ?? "?"

        let chain = DWEnvironment.sharedInstance().currentChain
        let networkSuffix = chain.isMainnet() ? "" : " (\(chain.name))"

        return "\(shortVersion) - \(buildVersion)\(networkSuffix)"
    }

    private static func makeDashSyncVersion() -> String {
        guard let path = Bundle.main.path(forResource: "DashSyncCurrentCommit", ofType: nil),
              let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            return "DashSync ?"
        }

        let commit = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortCommit = commit.count > 7 ? String(commit.prefix(7)) : commit
        return "\(shortCommit.isEmpty ? "?" : shortCommit)"
    }

    // MARK: - Preview

    private static var isRunningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private func applyPreviewData() {
        appVersion = "8.6.0 - 1"
        dashSyncVersion = "1a2b3c4"
        exploreStatus = "Synced"
        lastDeviceSync = "Jun 22, 2026 at 7:26 PM"
        lastDeviceUpdate = "Jun 22, 2026"
    }
}

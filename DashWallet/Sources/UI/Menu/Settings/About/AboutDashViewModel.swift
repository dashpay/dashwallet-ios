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
    @Published private(set) var exploreStatus: String = ""
    @Published private(set) var lastDeviceSync: String = ""
    @Published private(set) var lastDeviceUpdate: String = ""

    /// Non-nil presents the hidden shake-gesture diagnostics alert, carrying
    /// the tech-info snapshot taken when the shake landed.
    @Published var techInfo: String?
    /// True while the diagnostic-log archive is being staged + zipped.
    /// Guards re-entry from a second shake.
    @Published private(set) var isExportingLogs = false
    /// Non-nil presents the share sheet with the finished zip.
    @Published var exportedLogsURL: URL?
    /// Non-nil presents the log-export failure alert.
    @Published var logExportErrorMessage: String?

    let repositoryURL = "https://github.com/dashpay/dashwallet-ios"

    private var databaseObserver: NSObjectProtocol?
    private var shakeObserver: NSObjectProtocol?

    /// The ObjC About model still owns the tech-info status string
    /// (`status`), which reads DashSync-era + SwiftDashSDK state through
    /// `DWAboutModel+MasternodeSync`. Reused rather than reimplemented here.
    private lazy var aboutModel = DWAboutModel()

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

        // Hidden support gesture: shaking the device on this screen shows a
        // tech-info snapshot with copy / log-export actions. `DWWindow` posts
        // the notification; the observer lived on the old
        // `DWAboutViewController` and was dropped in the SwiftUI rewrite.
        shakeObserver = NotificationCenter.default.addObserver(
            forName: .DWDeviceDidShake,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDeviceShake()
            }
        }
    }

    deinit {
        if let databaseObserver {
            NotificationCenter.default.removeObserver(databaseObserver)
        }
        if let shakeObserver {
            NotificationCenter.default.removeObserver(shakeObserver)
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

    // MARK: - Shake diagnostics

    private func handleDeviceShake() {
        // A second shake while the alert is up would only re-read the same
        // state; keep the snapshot the user is looking at.
        guard techInfo == nil else { return }
        techInfo = aboutModel.status()
    }

    func copyTechInfo() {
        UIPasteboard.general.string = aboutModel.status()
    }

    /// Zip the recent diagnostic logs (SwiftDashSDK sessions + app
    /// CocoaLumberjack files) and hand the archive to the share sheet —
    /// the same export the Tools menu offers.
    func exportLogs() {
        guard !isExportingLogs else { return }
        isExportingLogs = true

        Task { [weak self] in
            let result = await DiagnosticLogExporter.exportArchive()
            guard let self else { return }
            self.isExportingLogs = false
            switch result {
            case .success(let url):
                self.exportedLogsURL = url
            case .failure(let error):
                self.logExportErrorMessage = error.localizedDescription
            }
        }
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

        let networkSuffix = WalletEnvironment.isMainnet
            ? ""
            : " (\(WalletEnvironment.networkDisplayName))"

        return "\(shortVersion) - \(buildVersion)\(networkSuffix)"
    }

    // MARK: - Preview

    private static var isRunningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private func applyPreviewData() {
        appVersion = "8.6.0 - 1"
        exploreStatus = "Synced"
        lastDeviceSync = "Jun 22, 2026 at 7:26 PM"
        lastDeviceUpdate = "Jun 22, 2026"
    }
}

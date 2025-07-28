//  
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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
import Combine

enum ToolsMenuNavigationDestination {
    case importPrivateKey
    case extendedPublicKeys
    case masternodeKeys
    case csvExport
    case zenLedger
}

@MainActor
class ToolsMenuViewModel: ObservableObject {
    @Published var items: [MenuItemModel] = []
    @Published var navigationDestination: ToolsMenuNavigationDestination?
    @Published var showCSVExportActivity = false
    @Published var csvExportData: (fileName: String, file: URL)?
    @Published var safariLink: String?
    
    init() {
        setupMenuItems()
    }
    
    private func setupMenuItems() {
        items = [
            MenuItemModel(
                title: NSLocalizedString("Import Private Key", comment: ""),
                icon: .custom("image.import.private.key", maxHeight: 22),
                action: { [weak self] in
                    self?.navigationDestination = .importPrivateKey
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("Extended Public Keys", comment: ""),
                icon: .custom("image.extend.public.key", maxHeight: 22),
                action: { [weak self] in
                    self?.navigationDestination = .extendedPublicKeys
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("Show Masternode Keys", comment: ""),
                icon: .custom("image.masternode.keys", maxHeight: 22),
                action: { [weak self] in
                    self?.navigationDestination = .masternodeKeys
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("CSV Export", comment: ""),
                icon: .custom("image.csv.export", maxHeight: 22),
                action: { [weak self] in
                    self?.navigationDestination = .csvExport
                }
            ),
            MenuItemModel(
                title: NSLocalizedString("ZenLedger", comment: ""),
                subtitle: NSLocalizedString("Simplify your crypto taxes", comment: ""),
                icon: .custom("zenledger"),
                action: { [weak self] in
                    self?.navigationDestination = .zenLedger
                }
            )
        ]
    }
    
    func resetNavigation() {
        navigationDestination = nil
        showCSVExportActivity = false
        csvExportData = nil
        safariLink = nil
    }
    
    func exportCSV() async throws {
        let result = try await generateCSVReport()
        csvExportData = result
        showCSVExportActivity = true
    }
    
    private func generateCSVReport() async throws -> (fileName: String, file: URL) {
        try await withCheckedThrowingContinuation { continuation in
            TaxReportGenerator.generateCSVReport(
                completionHandler: { fileName, file in
                    continuation.resume(returning: (fileName, file))
                },
                errorHandler: { error in
                    continuation.resume(throwing: error)
                }
            )
        }
    }
}

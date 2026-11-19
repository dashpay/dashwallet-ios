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

/// Draws `ExternalSendFlow`: Address, with Send pushed on it, and Select source, Confirm and Send failed as one bottom
/// sheet over Send. Every transition is the flow's; this view only mirrors its `step`.
struct ExternalSendFlowScreen: View {
    @ObservedObject var flow: ExternalSendFlow
    var onScan: () -> Void

    private enum Page: Hashable {
        case send
    }

    var body: some View {
        NavigationStack(path: pages) {
            addressPage
                .navigationDestination(for: Page.self) { _ in sendPage }
        }
        .sheet(isPresented: isSheetPresented) { sheet }
    }

    @ViewBuilder private var addressPage: some View {
        if let address = flow.addressViewModel {
            AddressScreen(viewModel: address, onBack: flow.backFromAddress, onScan: onScan)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder private var sendPage: some View {
        if let send = flow.sendViewModel {
            SendAmountScreen(
                viewModel: send, onBack: flow.backFromSend,
                onSelectSource: { Task { await flow.showSelectSource() } })
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var pages: Binding<[Page]> {
        Binding(
            get: { flow.sendViewModel != nil && flow.step != .address ? [.send] : [] },
            set: { if $0.isEmpty, flow.sendViewModel != nil { flow.backFromSend() } })
    }

    private var isSheetPresented: Binding<Bool> {
        Binding(get: { sheetContentIsShown }, set: { if !$0 { dismissSheet() } })
    }

    private var sheetContentIsShown: Bool {
        switch flow.step {
        case .selectSource, .confirm, .sendFailed: return true
        case .address, .send, .sent, nil: return false
        }
    }

    @ViewBuilder private var sheet: some View {
        switch flow.step {
        case .selectSource:
            if let select = flow.selectSourceViewModel {
                SelectSourceSheet(viewModel: select, onClose: flow.closeSelectSource)
            }
        case .confirm:
            if let confirm = flow.confirmViewModel { ConfirmSheet(viewModel: confirm) }
        case .sendFailed(let content):
            SendFailedSheet(content: content, isRetrying: flow.isRefetchingRequest, onClose: flow.closeFromSendFailed,
                            onRetry: flow.retryFromSendFailed)
        case .address, .send, .sent, nil:
            EmptyView()
        }
    }

    /// A swipe-down closes the sheet the way its own close button does.
    private func dismissSheet() {
        switch flow.step {
        case .selectSource: flow.closeSelectSource()
        case .confirm: flow.confirmViewModel?.cancel()
        case .sendFailed: flow.closeFromSendFailed()
        case .address, .send, .sent, nil: break
        }
    }
}

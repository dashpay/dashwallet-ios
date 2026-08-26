//
//  EvonodeStatusScreen.swift
//  DashWallet
//
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

import SwiftDashSDK
import SwiftUI

// MARK: - EvonodeStatusScreen

/// Everything one evonode answered to a DAPI `getStatus` request, grouped
/// as the node groups it. Pushed from the evonode detail screen's "Request
/// status" button; the request itself is sent when this screen appears and
/// again on Refresh — never on its own.
struct EvonodeStatusScreen: View {
    @StateObject private var viewModel: EvonodeStatusViewModel

    init(masternode: PlatformMasternode) {
        _viewModel = StateObject(wrappedValue: EvonodeStatusViewModel(masternode: masternode))
    }

    var body: some View {
        content
            .navigationTitle(NSLocalizedString("Node status", comment: "Evonode status"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.request() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                    .accessibilityLabel(NSLocalizedString("Refresh", comment: ""))
                }
            }
            .task {
                // The user reached this screen by tapping "Request status" —
                // that tap is the request. Re-appearing (back from a pushed
                // screen) keeps the last answer; Refresh asks again.
                if viewModel.phase == .idle {
                    await viewModel.request()
                }
            }
    }

    // MARK: Bodies

    /// A refresh keeps the previous answer on screen (with a small spinner)
    /// instead of blanking it; only the first request shows the full loader.
    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            loadingBody
        case .loading:
            if viewModel.sections.isEmpty {
                loadingBody
            } else {
                report
            }
        case .failed(let title, let detail):
            failedBody(title: title, detail: detail)
        case .loaded:
            report
        }
    }

    private var loadingBody: some View {
        VStack(spacing: 12) {
            // Explicitly SwiftUI's — the app declares its own `ProgressView`
            // UIKit class that shadows it here.
            SwiftUI.ProgressView()
            Text(NSLocalizedString("Asking the evonode…", comment: "Evonode status"))
                .font(.subheadline)
                .foregroundColor(Color.dash.secondaryText)
            if let address = viewModel.address {
                Text(address)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Color.dash.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedBody(title: String, detail: String?) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 40))
                .foregroundColor(Color.dash.tertiaryText)

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            if let address = viewModel.address {
                Text(address)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Color.dash.tertiaryText)
            }

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(Color.dash.secondaryText)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }

            if viewModel.address != nil {
                DashButton(
                    text: NSLocalizedString("Try again", comment: ""),
                    style: .filled,
                    stretch: false,
                    action: { Task { await viewModel.request() } })
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var report: some View {
        List {
            ForEach(viewModel.sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        switch row.style {
                        case .value:
                            MasternodeDetailRow(label: row.label, value: row.value)
                        case .copyable:
                            MasternodeCopyRow(label: row.label, value: row.value)
                        }
                    }
                } header: {
                    Text(section.title)
                } footer: {
                    if let footer = section.footer {
                        Text(footer)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if viewModel.isLoading {
                SwiftUI.ProgressView()
                    .padding(8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }
}

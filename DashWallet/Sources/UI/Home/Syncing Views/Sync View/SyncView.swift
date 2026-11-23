//
//  Created by PT
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

import SwiftUI

// MARK: - SyncView

/// The card under the shortcut bar that reports a sync the wallet cannot
/// continue: no connection, or a failed sync with a retry button. Hidden
/// while the wallet syncs or is synced; the transaction list header shows
/// that progress instead.
struct SyncView: View {
    // `@StateObject`: `SyncModelImpl.init` registers with the shared sync
    // monitor, which holds it, so a model built on every re-init would leak.
    @StateObject private var model = SyncModelImpl()
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass
    let onRetry: () -> Void

    private enum Status {
        case noConnection
        case failed
    }

    private var status: Status? {
        switch model.state {
        case .noConnection:
            return .noConnection
        case .syncFailed:
            return model.networkStatus == .online ? .failed : .noConnection
        default:
            return nil
        }
    }

    var body: some View {
        if let status {
            card(status)
                .padding(.horizontal, horizontalSizeClass == .regular ? 20 : 16)
                .padding(.vertical, 8)
        }
    }

    private func card(_ status: Status) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title(status))
                    .font(Font(UIFont.dw_font(forTextStyle: .subheadline)))
                    .foregroundColor(Color(uiColor: status == .noConnection ? .dw_lightTitle() : .dw_secondaryText()))
                Text(subtitle(status))
                    .font(Font(UIFont.dw_font(forTextStyle: .footnote)))
                    .foregroundColor(Color(uiColor: status == .noConnection ? .dw_lightTitle() : .dw_quaternaryText()))
            }
            .padding(.leading, 7)
            .padding(.vertical, 5)

            Spacer(minLength: 0)

            Button(action: retry) {
                Image("icon_reload")
                    .renderingMode(.template)
                    .foregroundColor(Color(uiColor: status == .noConnection ? .dw_background() : .dw_red()))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text(NSLocalizedString("Retry", comment: "")))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 70)
        .overlay(alignment: .bottom) {
            if status == .failed {
                progressBar
            }
        }
        .background(Color(uiColor: status == .noConnection ? .dw_red() : .dw_background()))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: Color(uiColor: .dw_shadow()).opacity(0.02), radius: 2.5)
    }

    /// How far the sync got before it failed.
    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Color(uiColor: .dw_progressBackground())
                Color(uiColor: .dw_green())
                    .frame(width: proxy.size.width * min(max(model.progress, 0), 1))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    private func title(_ status: Status) -> String {
        switch status {
        case .noConnection: NSLocalizedString("Unable to connect", comment: "")
        case .failed: NSLocalizedString("Sync Failed", comment: "")
        }
    }

    private func subtitle(_ status: Status) -> String {
        switch status {
        case .noConnection: NSLocalizedString("Check your connection", comment: "")
        case .failed: NSLocalizedString("Please try again", comment: "")
        }
    }

    private func retry() {
        model.forceStartSyncingActivity()
        onRetry()
    }
}

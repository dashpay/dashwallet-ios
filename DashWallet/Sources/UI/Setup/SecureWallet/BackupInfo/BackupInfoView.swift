//
//  Created by Dash Core Group
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

// MARK: - BackupInfoViewModel

/// What the backup info screen shows. The flow behind its buttons stays in
/// `BackupInfoViewController`.
@MainActor
final class BackupInfoViewModel: ObservableObject {
    @Published var isSkipButtonHidden = true
    /// The screen only explains, with no buttons: opened from "Why I should
    /// not take a screenshot?".
    @Published var areActionsHidden = false

    /// The 12 / 24 words choice, offered only while a new wallet is still to
    /// be created.
    @Published var phraseLength: RecoveryPhraseLengthPickerModel?

    var onShowPhrase: () -> Void = { }
    var onSkip: () -> Void = { }
}

// MARK: - BackupInfoView

/// Why the recovery phrase matters, before it is shown: Dash Core Group does
/// not keep it, and the wallet cannot be restored without it.
struct BackupInfoView: View {
    @ObservedObject var viewModel: BackupInfoViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    Image("backup-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .accessibilityHidden(true)

                    VStack(spacing: 5) {
                        Text(String(localized: "Backup your recovery phrase", comment: "Back up wallet"))
                            .font(.system(.title2))
                            .accessibilityAddTraits(.isHeader)
                        Text(String(localized: "You will need this recovery phrase to access your funds if this device is lost, damaged or if Dash Wallet is uninstalled from this device.",
                                    comment: "Back up wallet"))
                            .font(.system(.subheadline))
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)

                    VStack(alignment: .leading, spacing: 18) {
                        BackupInfoItemRow(item: .notStoredByDash)
                        BackupInfoItemRow(item: .unableToRestore)
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)

            if !viewModel.areActionsHidden {
                VStack(spacing: 8) {
                    if let phraseLength = viewModel.phraseLength {
                        RecoveryPhraseLengthPickerHost(model: phraseLength)
                            .padding(.bottom, 12)
                    }
                    Button(String(localized: "Show Recovery Phrase", comment: "Back up wallet"),
                           action: viewModel.onShowPhrase)
                        .buttonStyle(SetupActionButtonStyle())
                    if !viewModel.isSkipButtonHidden {
                        Button(String(localized: "Skip", comment: "Back up wallet"), action: viewModel.onSkip)
                            .buttonStyle(SetupTextButtonStyle())
                    }
                }
                .padding(.horizontal, 15)
                .padding(.bottom, 4)
            }
        }
        .background(Color("SecondaryBackgroundColor").ignoresSafeArea())
    }
}

// MARK: - BackupInfoItem

enum BackupInfoItem {
    case notStoredByDash
    case unableToRestore

    var title: String {
        switch self {
        case .notStoredByDash:
            return String(localized: "Dash Core Group does NOT store this recovery phrase",
                          comment: "Recovery phrase backup: security warning title — Dash Core Group does not store the phrase")
        case .unableToRestore:
            return String(localized: "You will NOT be able to restore the wallet without a recovery phrase",
                          comment: "Recovery phrase backup: security warning title — the phrase is required to restore the wallet")
        }
    }

    var description: String {
        switch self {
        case .notStoredByDash:
            return String(localized: "Anyone that has your recovery phrase can access your funds.",
                          comment: "Recovery phrase backup: security warning body — anyone with the phrase can spend the funds")
        case .unableToRestore:
            return String(localized: "Write it in a safe place and don’t show it to anyone.",
                          comment: "Recovery phrase backup: security warning body — keep the phrase written down and private")
        }
    }

    var icon: String {
        switch self {
        case .notStoredByDash: return "backup-not-stored-icon"
        case .unableToRestore: return "backup-recovery-icon"
        }
    }
}

private struct BackupInfoItemRow: View {
    let item: BackupInfoItem

    var body: some View {
        HStack(alignment: .titleCenter, spacing: 18) {
            Image(item.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .alignmentGuide(.titleCenter) { $0[VerticalAlignment.center] }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                // The icon is centred on the title.
                Text(item.title)
                    .font(.system(.subheadline, weight: .semibold))
                    .alignmentGuide(.titleCenter) { $0[VerticalAlignment.center] }
                Text(item.description)
                    .font(.system(.footnote))
                    .foregroundColor(Color("SecondaryTextColor"))
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private extension VerticalAlignment {
    enum TitleCenter: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    static let titleCenter = VerticalAlignment(TitleCenter.self)
}

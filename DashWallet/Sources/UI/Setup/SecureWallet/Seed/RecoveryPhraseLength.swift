//
//  RecoveryPhraseLength.swift
//  DashWallet
//
//  Created by Dash Core Group.
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

import DashUIKit
import SwiftUI

// MARK: - RecoveryPhraseLength

/// The BIP39 word counts a user can pick when creating a new wallet.
///
/// SwiftDashSDK's `Mnemonic.generate(wordCount:)` accepts 12/15/18/21/24;
/// the app offers the two lengths people actually ask for. Restoring keeps
/// accepting every BIP39 length regardless of this choice.
enum RecoveryPhraseLength: Int, CaseIterable, Identifiable {
    case twelve = 12
    case twentyFour = 24

    /// What a fresh wallet gets when the user doesn't choose (the historical
    /// app behaviour).
    static let `default`: RecoveryPhraseLength = .twelve

    var id: Int { rawValue }

    /// The value handed to `Mnemonic.generate(wordCount:)`.
    var wordCount: UInt32 { UInt32(rawValue) }

    /// Segment label: "12 words" / "24 words".
    var title: String {
        String.localizedStringWithFormat(
            NSLocalizedString("%d words", comment: "Recovery phrase length (plural-aware)"),
            rawValue)
    }
}

// MARK: - RecoveryPhraseLengthPicker

/// Segmented 12 / 24-word choice shown before a new recovery phrase is
/// generated. Shared by onboarding (`BackupInfoViewController`, hosted) and
/// the multi-wallet "Create New Wallet" sheet (`WalletsScreen`).
struct RecoveryPhraseLengthPicker: View {
    @Binding var selection: RecoveryPhraseLength

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Recovery phrase length", comment: "Recovery phrase length"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.dash.secondaryText)

            Picker(
                NSLocalizedString("Recovery phrase length", comment: "Recovery phrase length"),
                selection: $selection
            ) {
                ForEach(RecoveryPhraseLength.allCases) { length in
                    Text(length.title).tag(length)
                }
            }
            .pickerStyle(.segmented)

            Text(NSLocalizedString(
                "12 words is the standard. 24 words is longer to write down and restore, but harder to guess.",
                comment: "Recovery phrase length"))
                .font(.system(size: 12))
                .foregroundColor(.dash.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - RecoveryPhraseLengthPickerHost

/// UIKit-hostable wrapper around `RecoveryPhraseLengthPicker`: owns the
/// selection and reports every change to the hosting controller, which keeps
/// the authoritative value (it's read at wallet-creation time, not bound).
struct RecoveryPhraseLengthPickerHost: View {
    @State private var selection: RecoveryPhraseLength
    private let onChange: (RecoveryPhraseLength) -> Void

    init(initial: RecoveryPhraseLength, onChange: @escaping (RecoveryPhraseLength) -> Void) {
        _selection = State(initialValue: initial)
        self.onChange = onChange
    }

    var body: some View {
        RecoveryPhraseLengthPicker(selection: $selection)
            .onChange(of: selection) { _, newValue in onChange(newValue) }
    }
}

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

// MARK: - RecoveryPhraseViewModel

/// The recovery phrase, either to write down while backing up the wallet or
/// to look at again from Security.
@MainActor
final class RecoveryPhraseViewModel: ObservableObject {
    enum Mode {
        /// Backing up: "I wrote it down" unlocks Continue, which goes on to
        /// verify the phrase.
        case backup
        /// Viewing it again: a warning against screenshots, and Done.
        case preview
    }

    let mode: Mode
    let seedPhrase: DWSeedPhraseModel
    let words: [String]

    /// How many words have appeared so far: they come in one after another.
    @Published private(set) var visibleWords = 0
    /// "I wrote it down" shows a moment after the words, so it is not ticked
    /// before the phrase has been read.
    @Published private(set) var isConfirmationVisible = false
    @Published var isConfirmed = false

    /// The time each word takes to appear.
    static let wordAppearance: TimeInterval = 0.065
    private static let confirmationDelay: TimeInterval = 2

    private var hasAppeared = false

    init(mode: Mode, seedPhrase: DWSeedPhraseModel) {
        self.mode = mode
        self.seedPhrase = seedPhrase
        words = seedPhrase.words.map(\.word)
    }

    var canContinue: Bool {
        mode == .preview || isConfirmed
    }

    /// Shows the words one by one, the first time the screen appears.
    func appear(reduceMotion: Bool) async {
        guard !hasAppeared else { return }
        hasAppeared = true

        if mode == .backup {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.confirmationDelay))
                withAnimation(.easeInOut(duration: 0.3)) { self?.isConfirmationVisible = true }
            }
        }

        guard !reduceMotion else {
            visibleWords = words.count
            return
        }
        for count in 1 ... max(words.count, 1) {
            withAnimation(.linear(duration: Self.wordAppearance)) { visibleWords = count }
            try? await Task.sleep(for: .seconds(Self.wordAppearance))
        }
    }

    #if DEBUG
    /// Long press, debug builds only: copies the phrase for testing.
    func copyForDebugging() {
        UIPasteboard.general.string = words.joined(separator: " ")
    }
    #endif
}

// MARK: - RecoveryPhraseView

struct RecoveryPhraseView: View {
    @ObservedObject var viewModel: RecoveryPhraseViewModel
    var onContinue: () -> Void = { }
    var onWhyNoScreenshot: () -> Void = { }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        phrase
                        Spacer(minLength: 16)
                        footer
                    }
                    // More room above the phrase when the screen has it.
                    .padding(.top, proxy.size.height - contentHeight >= 128 ? 64 : 16)
                    // 12 below the footer, and 16 above the button.
                    .padding(.bottom, 28)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            Button(viewModel.mode == .backup
                ? String(localized: "Continue", comment: "")
                : String(localized: "Done", comment: ""),
                action: onContinue)
                .buttonStyle(SetupActionButtonStyle())
                .disabled(!viewModel.canContinue)
                .accessibilityIdentifier("seedphrase_continue_button")
                .padding(.bottom, 4)
        }
        .padding(.horizontal, 16)
        .background(Color("SecondaryBackgroundColor").ignoresSafeArea())
        .task { await viewModel.appear(reduceMotion: reduceMotion) }
    }

    private var phrase: some View {
        VStack(spacing: 20) {
            if viewModel.mode == .backup {
                Text(String(localized: "Please write it down", comment: ""))
                    .font(.system(.title3))
                    .foregroundColor(Color("DarkTitleColor"))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
            } else {
                // The phrase sits where it does under the backup title.
                Color.clear.frame(height: 0)
            }

            RecoveryPhraseWords(words: viewModel.words, visibleWords: viewModel.visibleWords)
                #if DEBUG
                .onLongPressGesture { viewModel.copyForDebugging() }
                #endif

            if viewModel.mode == .preview {
                VStack(spacing: 16) {
                    Image("icon_screenshot_warning")
                        .accessibilityHidden(true)
                    Text(String(localized: "WARNING", comment: "") + "\n"
                        + String(localized: "Do not take a screenshot", comment: ""))
                        .font(.system(.subheadline))
                        .foregroundColor(Color("RedColor"))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            // The phrase plus the footer, to decide on the top padding.
            contentHeight = height + 16 + 44 + 28 + 16
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch viewModel.mode {
        case .backup:
            RecoveryPhraseCheckbox(
                title: String(localized: "I wrote it down", comment: ""),
                isOn: $viewModel.isConfirmed
            )
            .opacity(viewModel.isConfirmationVisible ? 1 : 0)
            .disabled(!viewModel.isConfirmationVisible)
            .accessibilityHidden(!viewModel.isConfirmationVisible)
            .accessibilityIdentifier("seedphrase_checkbox")
        case .preview:
            Button(String(localized: "Why I should not take a screenshot?", comment: ""), action: onWhyNoScreenshot)
                .font(.system(.body))
                .foregroundColor(Color.dash.blue)
                .multilineTextAlignment(.center)
                .frame(minHeight: 44)
        }
    }
}

// MARK: - RecoveryPhraseWords

/// The words on a card, in centred rows of up to four.
struct RecoveryPhraseWords: View {
    let words: [String]
    var visibleWords: Int

    var body: some View {
        RecoveryPhraseRowsLayout(maxPerRow: 4) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(word)
                    .font(.system(.body))
                    .foregroundColor(Color.dash.blue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .opacity(index < visibleWords ? 1 : 0)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color("BackgroundColor"))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Recovery Phrase", comment: ""))
        // Only the words shown so far: while verifying, the rest are still
        // to be picked.
        .accessibilityValue(words.prefix(visibleWords).joined(separator: ", "))
    }
}

/// Lays the words out in rows, each centred and holding as many words as
/// fit, up to `maxPerRow`, `spacing` apart both ways.
struct RecoveryPhraseRowsLayout: Layout {
    var maxPerRow: Int
    var spacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(for: subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for (index, size) in zip(row.indices, row.sizes) {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if !row.indices.isEmpty
                && (row.indices.count == maxPerRow || row.width + spacing + size.width > width) {
                rows.append(row)
                row = Row()
            }
            row.width += row.indices.isEmpty ? size.width : spacing + size.width
            row.indices.append(index)
            row.sizes.append(size)
            row.height = max(row.height, size.height)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: - RecoveryPhraseCheckbox

/// A round checkbox with its title, centred.
struct RecoveryPhraseCheckbox: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(isOn ? "icon_checkbox_checked" : "icon_checkbox")
                Text(title)
                    .font(.system(.callout))
                    .foregroundColor(Color("SecondaryTextColor"))
                    .multilineTextAlignment(.leading)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

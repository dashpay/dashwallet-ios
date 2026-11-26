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
import UniformTypeIdentifiers

// MARK: - VerifyRecoveryPhraseViewModel

/// Checks that the recovery phrase was written down: the user picks its
/// words, shuffled, in the right order.
@MainActor
final class VerifyRecoveryPhraseViewModel: ObservableObject {
    struct Tile: Identifiable, Equatable {
        let id: Int
        let word: String
    }

    let words: [String]

    /// The words to pick from. In the phrase's order at first, then shuffled
    /// once the screen is up, so the user sees them move.
    @Published private(set) var tiles: [Tile]
    /// How many words, from the start of the phrase, have been picked.
    @Published private(set) var verifiedCount = 0
    @Published private(set) var pickedTiles: Set<Int> = []
    /// A tile picked out of order flashes red and shakes.
    @Published private(set) var rejectedTiles: Set<Int> = []
    @Published private(set) var shakes: [Int: CGFloat] = [:]

    /// Called once the last word is picked.
    var onVerified: () -> Void = { }

    /// The tile being dragged onto the phrase, if any.
    var draggedTile: Tile?

    /// The time a picked word takes to appear in the phrase.
    static let wordAppearance: TimeInterval = 0.25
    private static let shuffleStep: TimeInterval = 0.065

    private let shuffledTiles: [Tile]
    private var hasAppeared = false

    init(seedPhrase: DWSeedPhraseModel) {
        words = seedPhrase.words.map(\.word)
        let tiles = words.enumerated().map { Tile(id: $0.offset, word: $0.element) }
        self.tiles = tiles
        shuffledTiles = tiles.shuffled()
    }

    var isVerified: Bool {
        verifiedCount == words.count
    }

    func appear(reduceMotion: Bool) {
        guard !hasAppeared else { return }
        hasAppeared = true

        let animation: Animation? = reduceMotion
            ? nil
            : .easeInOut(duration: Self.shuffleStep * Double(tiles.count))
        withAnimation(animation) { tiles = shuffledTiles }
    }

    func isPicked(_ tile: Tile) -> Bool {
        pickedTiles.contains(tile.id)
    }

    /// Whether `tile` holds the next word of the phrase. The same word can be
    /// in the phrase twice, so any tile with it will do.
    func canPick(_ tile: Tile) -> Bool {
        !isPicked(tile) && !isVerified && tile.word == words[verifiedCount]
    }

    func tap(_ tile: Tile) {
        guard !isPicked(tile), !isVerified else { return }

        if canPick(tile) {
            pick(tile)
        }
        else {
            reject(tile)
        }
    }

    /// Picks the tile being dragged, when it is dropped on the phrase.
    @discardableResult
    func dropDraggedTile() -> Bool {
        defer { draggedTile = nil }
        guard let tile = draggedTile, canPick(tile) else { return false }
        pick(tile)
        return true
    }

    private func pick(_ tile: Tile) {
        pickedTiles.insert(tile.id)
        withAnimation(.easeInOut(duration: Self.wordAppearance)) { verifiedCount += 1 }

        guard isVerified else { return }
        DWGlobalOptions.sharedInstance().walletNeedsBackup = false

        // Show the result once the last word has appeared.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.wordAppearance))
            self?.onVerified()
        }
    }

    private func reject(_ tile: Tile) {
        guard !rejectedTiles.contains(tile.id) else { return }

        withAnimation(.linear(duration: 0.1)) { _ = rejectedTiles.insert(tile.id) }
        withAnimation(.linear(duration: 0.35).delay(0.1)) { shakes[tile.id, default: 0] += 1 }

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.45))
            withAnimation(.linear(duration: 0.1)) { _ = self?.rejectedTiles.remove(tile.id) }
        }
    }
}

// MARK: - VerifyRecoveryPhraseView

struct VerifyRecoveryPhraseView: View {
    @ObservedObject var viewModel: VerifyRecoveryPhraseViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phraseHeight: CGFloat = 0
    @State private var choiceHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    phrase
                    Spacer(minLength: 24)
                    choice
                }
                // More room above the phrase when the screen has it.
                .padding(.top, proxy.size.height - (16 + phraseHeight + 24 + choiceHeight + 12) >= 128 ? 64 : 16)
                .padding(.bottom, 12)
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, 16)
        .background(Color("SecondaryBackgroundColor").ignoresSafeArea())
        .onAppear { viewModel.appear(reduceMotion: reduceMotion) }
    }

    private var phrase: some View {
        VStack(spacing: 20) {
            Text(String(localized: "Verify", comment: ""))
                .font(.system(.title3))
                .foregroundColor(Color("DarkTitleColor"))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            RecoveryPhraseWords(words: viewModel.words, visibleWords: viewModel.verifiedCount)
                .onDrop(of: [RecoveryPhraseWordTile.dragType],
                        delegate: RecoveryPhraseDropDelegate(viewModel: viewModel))
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { phraseHeight = $0 }
    }

    private var choice: some View {
        VStack(spacing: 16) {
            Text(String(localized: "Please tap on the words from your recovery phrase in the right order", comment: ""))
                .font(.system(.callout))
                .foregroundColor(Color("SecondaryTextColor"))
                .multilineTextAlignment(.center)

            RecoveryPhraseRowsLayout(maxPerRow: 4, spacing: 8) {
                ForEach(viewModel.tiles) { tile in
                    RecoveryPhraseWordTile(tile: tile, viewModel: viewModel)
                }
            }
            .padding(.vertical, 8)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { choiceHeight = $0 }
    }
}

// MARK: - RecoveryPhraseWordTile

/// A word to pick: Dash blue, grey once picked, red for a moment when picked
/// out of order. It can also be dragged onto the phrase.
private struct RecoveryPhraseWordTile: View {
    let tile: VerifyRecoveryPhraseViewModel.Tile
    @ObservedObject var viewModel: VerifyRecoveryPhraseViewModel

    /// Known only to this app, and offered only within it: a word of the
    /// phrase must not be dropped into another app.
    static let dragType = "org.dashfoundation.dash.recovery-phrase-word"

    private var isPicked: Bool { viewModel.isPicked(tile) }

    var body: some View {
        Button {
            viewModel.tap(tile)
        } label: {
            Text(tile.word)
                .font(.system(.footnote))
                .foregroundColor(Color("LightTitleColor"))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 20)
                .padding(.vertical, 13)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .modifier(ShakeEffect(shakes: viewModel.shakes[tile.id, default: 0]))
        .modifier(WordDrag(isEnabled: !isPicked) { viewModel.draggedTile = tile })
        .accessibilityAddTraits(isPicked ? [.isSelected] : [])
    }

    private var background: Color {
        if viewModel.rejectedTiles.contains(tile.id) {
            return Color("RedColor")
        }
        return isPicked ? Color("DisabledButtonColor") : Color.dash.blue
    }
}

/// Lets an unpicked word be dragged, within the app only.
private struct WordDrag: ViewModifier {
    let isEnabled: Bool
    let onStart: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.onDrag {
                onStart()
                let provider = NSItemProvider()
                provider.registerDataRepresentation(forTypeIdentifier: RecoveryPhraseWordTile.dragType,
                                                    visibility: .ownProcess) { completion in
                    // The dragged word is known to the view model; the drag
                    // itself carries nothing.
                    completion(Data(), nil)
                    return nil
                }
                return provider
            }
        }
        else {
            content
        }
    }
}

/// Accepts a dragged word on the phrase when it is the next one.
private struct RecoveryPhraseDropDelegate: DropDelegate {
    let viewModel: VerifyRecoveryPhraseViewModel

    func validateDrop(info: DropInfo) -> Bool {
        viewModel.draggedTile != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let canPick = viewModel.draggedTile.map(viewModel.canPick) ?? false
        return DropProposal(operation: canPick ? .move : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        viewModel.dropDraggedTile()
    }
}

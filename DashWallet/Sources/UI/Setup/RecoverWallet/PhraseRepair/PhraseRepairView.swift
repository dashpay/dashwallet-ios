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

// MARK: - PhraseRepairViewModel

/// Looks for the word that should replace a wrong one, or for the words
/// missing at the end of a 10 or 11 word phrase.
@MainActor
final class PhraseRepairViewModel: ObservableObject, Identifiable {
    enum State: Equatable {
        case searching
        /// Found for certain.
        case found(String)
        /// Candidates, the likeliest first.
        case candidates([String])
        case notFound
    }

    /// Runs the search: progress ticks (writing true stops it) and the words
    /// found, each with its confidence, lower being better.
    typealias Search = (
        _ progress: @escaping (Float, UnsafeMutablePointer<ObjCBool>) -> Void,
        _ completion: @escaping ([String: NSNumber]) -> Void
    ) -> Void

    @Published private(set) var state: State = .searching
    @Published private(set) var progress: Float = 0
    @Published private(set) var isCancelling = false

    /// The words chosen, empty when none.
    var onFinish: ([String]) -> Void = { _ in }

    /// Candidates offered as buttons, at most.
    static let maxCandidates = 5

    private let search: Search
    private let maxConfidence: UInt
    private var hasFinished = false

    init(phrase: String, incorrectWord: String?) {
        maxConfidence = SwiftDashSDKPhraseRepairer.maxConfidence
        if let incorrectWord {
            search = { progress, completion in
                SwiftDashSDKPhraseRepairer.findPotentialWords(passphrase: phrase,
                                                              replacementString: incorrectWord,
                                                              progressUpdate: progress,
                                                              completion: completion)
            }
        } else {
            search = { progress, completion in
                SwiftDashSDKPhraseRepairer.findLastPotentialWords(passphrase: phrase,
                                                                  progressUpdate: progress,
                                                                  completion: completion)
            }
        }
    }

    init(search: @escaping Search, maxConfidence: UInt) {
        self.search = search
        self.maxConfidence = maxConfidence
    }

    var title: String {
        switch state {
        case .searching:
            return String(localized: "Recovering...", comment: "")
        case .found(let words):
            return words.contains(" ")
                ? String(format: String(localized: "Found missing words:\n%@", comment: ""), words)
                : String(format: String(localized: "Found missing word:\n%@", comment: ""), words)
        case .candidates(let words):
            return String(format: String(localized: "Found potential missing words:\n%@", comment: ""),
                          words.joined(separator: "\n"))
        case .notFound:
            return String(localized: "Could not automatically recover missing or incorrect words", comment: "")
        }
    }

    func start() {
        search({ [weak self] progress, stop in
            // The repairer calls back on the main queue.
            MainActor.assumeIsolated {
                guard let self, !self.hasFinished else { return }
                self.progress = progress
                if self.isCancelling {
                    stop.pointee = true
                    self.finish(with: [])
                }
            }
        }, { [weak self] words in
            MainActor.assumeIsolated {
                self?.complete(with: words)
            }
        })
    }

    func complete(with words: [String: NSNumber]) {
        guard !hasFinished else { return }
        guard !isCancelling else {
            finish(with: [])
            return
        }
        progress = 1
        if words.count == 1, let (word, confidence) = words.first, confidence.uintValue == maxConfidence {
            state = .found(word)
        } else if !words.isEmpty {
            // Likeliest first; equally likely ones in alphabetical order.
            let sorted = words.sorted {
                $0.value == $1.value ? $0.key < $1.key : $0.value.compare($1.value) == .orderedAscending
            }
            state = .candidates(sorted.map(\.key))
        } else {
            state = .notFound
        }
    }

    /// Cancel while searching: stops at the next progress tick.
    func cancel() {
        isCancelling = true
    }

    /// OK, or Cancel once the search is over.
    func dismiss() {
        switch state {
        case .found(let words):
            finish(with: [words])
        default:
            finish(with: [])
        }
    }

    func choose(_ word: String) {
        finish(with: [word])
    }

    private func finish(with words: [String]) {
        guard !hasFinished else { return }
        hasFinished = true
        onFinish(words)
    }
}

// MARK: - PhraseRepairView

/// Progress of the phrase repair and its result, on an alert-like card.
struct PhraseRepairView: View {
    @ObservedObject var viewModel: PhraseRepairViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                VStack(spacing: 32) {
                    Text(viewModel.title)
                        .font(.system(.headline))
                        .foregroundColor(Color("DarkTitleColor"))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 16)
                        .accessibilityAddTraits(.isHeader)

                    SwiftUI.ProgressView(value: viewModel.progress)
                        .progressViewStyle(RepairProgressStyle())
                }
                .padding(.top, 20)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)

                actions
            }
            .frame(width: 270)
            .background(Color("SecondaryBackgroundColor"))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        // Centred on the screen, as an alert is.
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var actions: some View {
        switch viewModel.state {
        case .searching:
            action(String(localized: "Cancel", comment: ""), isCancel: true, action: viewModel.cancel)
                .disabled(viewModel.isCancelling)
        case .found, .notFound:
            action(String(localized: "OK", comment: ""), isCancel: true, action: viewModel.dismiss)
        case .candidates(let words):
            ForEach(words.prefix(PhraseRepairViewModel.maxCandidates), id: \.self) { word in
                action(word, isCancel: false) { viewModel.choose(word) }
            }
            action(String(localized: "Cancel", comment: ""), isCancel: true, action: viewModel.dismiss)
        }
    }

    private func action(_ title: String, isCancel: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: action) {
                Text(title)
                    .font(.system(.body, weight: isCancel ? .semibold : .regular))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(Color.dash.blue)
        }
    }
}

/// A 5pt bar: green over the progress track.
private struct RepairProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color("ProgressBackgroundColor"))
                Rectangle()
                    .fill(Color("GreenColor"))
                    .frame(width: proxy.size.width * CGFloat(configuration.fractionCompleted ?? 0))
                    .animation(.easeOut(duration: 0.25), value: configuration.fractionCompleted)
            }
        }
        .frame(height: 5)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

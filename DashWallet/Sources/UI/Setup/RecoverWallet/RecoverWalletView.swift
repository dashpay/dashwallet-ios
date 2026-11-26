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
import UIKit

// MARK: - RecoverWalletView

/// Entering the recovery phrase, then Continue.
struct RecoverWalletView: View {
    @ObservedObject var viewModel: RecoverWalletViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    Text(viewModel.heading)
                        .font(.system(.title2))
                        .foregroundColor(Color("DarkTitleColor"))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    RecoveryPhraseTextView(
                        text: $viewModel.phrase,
                        focusRequests: viewModel.focusRequests,
                        selection: viewModel.selection,
                        onReturn: viewModel.submit
                    )
                    .accessibilityLabel(viewModel.heading)
                }
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.never)

            Button(String(localized: "Continue", comment: ""), action: viewModel.submit)
                .buttonStyle(SetupActionButtonStyle())
                .disabled(!viewModel.canContinue)
                .padding(.bottom, UIDevice.isIpad ? 24 : 4)
        }
        .padding(.horizontal, 16)
        .background(Color("SecondaryBackgroundColor").ignoresSafeArea())
        .alert(viewModel.alert?.title ?? "",
               isPresented: Binding(get: { viewModel.alert != nil },
                                    set: { if !$0 { viewModel.alert = nil } }),
               presenting: viewModel.alert) { alert in
            ForEach(Array(alert.actions.enumerated()), id: \.offset) { _, action in
                Button(action.title, role: action.role.buttonRole, action: action.handler)
            }
        } message: { alert in
            if let message = alert.message {
                Text(message)
            }
        }
    }
}

private extension RecoverWalletViewModel.Alert.Action.Role {
    var buttonRole: ButtonRole? {
        switch self {
        case .cancel: return .cancel
        case .destructive: return .destructive
        case .plain: return nil
        }
    }
}

// MARK: - RecoveryPhraseTextView

/// The phrase being typed: Dash blue words, centred, with room for five
/// lines and Done on the keyboard to continue. A text view rather than a
/// `TextEditor`, which can neither take Done for Return nor select a word.
struct RecoveryPhraseTextView: UIViewRepresentable {
    @Binding var text: String
    var focusRequests: Int
    var selection: (word: String, request: Int)?
    var onReturn: () -> Void

    private static let insets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    /// Between lines, as between the words of the phrase elsewhere.
    fileprivate static let lineSpacing: CGFloat = 10
    private static let minimumLines = 5

    func makeUIView(context: Context) -> UITextView {
        let textView = PhraseTextView()
        textView.delegate = context.coordinator
        textView.layoutManager.delegate = context.coordinator
        textView.backgroundColor = UIColor(named: "BackgroundColor")
        textView.layer.cornerRadius = 8
        textView.layer.masksToBounds = true
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .dw_dashBlue()
        textView.textContainerInset = Self.insets
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.returnKeyType = .done
        textView.textAlignment = .center
        textView.isScrollEnabled = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        if textView.text != text {
            textView.text = text
        }
        if context.coordinator.focusRequests != focusRequests {
            context.coordinator.focusRequests = focusRequests
            DispatchQueue.main.async { textView.becomeFirstResponder() }
        }
        if let selection, context.coordinator.selectionRequest != selection.request {
            context.coordinator.selectionRequest = selection.request
            let range = (textView.text.lowercased() as NSString).range(of: selection.word)
            if range.location != NSNotFound {
                textView.selectedRange = range
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView textView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        let fitting = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fitting.height, minimumHeight(for: textView.font)))
    }

    private func minimumHeight(for font: UIFont?) -> CGFloat {
        let lineHeight = ceil((font ?? .preferredFont(forTextStyle: .body)).lineHeight)
        let lines = CGFloat(Self.minimumLines)
        return lineHeight * lines + Self.lineSpacing * (lines - 1) + Self.insets.top + Self.insets.bottom
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate, NSLayoutManagerDelegate {
        var parent: RecoveryPhraseTextView
        var focusRequests = 0
        var selectionRequest = 0

        init(parent: RecoveryPhraseTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            guard text == "\n" else { return true }
            parent.onReturn()
            return false
        }

        func layoutManager(_ layoutManager: NSLayoutManager,
                           lineSpacingAfterGlyphAt glyphIndex: Int,
                           withProposedLineFragmentRect rect: CGRect) -> CGFloat {
            RecoveryPhraseTextView.lineSpacing
        }
    }
}

/// Keeps the caret as tall as the letters, not the line with its spacing.
private final class PhraseTextView: UITextView {
    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        if let font {
            rect.size.height = font.pointSize - font.descender
        }
        return rect
    }
}

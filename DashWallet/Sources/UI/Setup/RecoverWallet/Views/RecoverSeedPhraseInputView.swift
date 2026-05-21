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
import UIKit

#if SEED_INPUT_DIAGNOSTICS
// TEMPORARY: Seed input diagnostics for targeted TestFlight troubleshooting.
// Enable only in dedicated diagnostic builds and disable/remove before release.
// Build setting: OTHER_SWIFT_FLAGS = $(inherited) -D SEED_INPUT_DIAGNOSTICS
private enum RecoverSeedPhraseInputDebugLog {
    static let isEnabled = true

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        // TODO: Verify this NSLog stream is included in logs received from
        // remote TestFlight users for this diagnostic campaign.
        NSLog("[RecoverSeedInput] %@", message())
    }
}
#endif

/// Stage 1 SwiftUI replacement for the seed-entry portion of the legacy
/// recovery wallet flow (`DWRecoverContentView` + `DWRecoverTextView`).
///
/// This view intentionally contains no recovery, wipe, or validation logic —
/// it is presentation and input only, so it can be iterated on and previewed
/// in isolation without touching the existing Objective-C production flow.
///
/// The underlying multiline editor is implemented as a `UIViewRepresentable`
/// wrapper around `UITextView` (instead of SwiftUI's `TextEditor`). That gives
/// us deterministic background, padding, and text-alignment behaviour on all
/// supported iOS versions (the project's deployment target is iOS 15, while
/// `scrollContentBackground(.hidden)` only works from iOS 16). It also leaves
/// a single place where additional UIKit text-input flags can be tightened in
/// later migration stages (e.g. `spellCheckingType`, `inlinePredictionType`,
/// `writingToolsBehavior`, ASCII-only keyboard).
struct RecoverSeedPhraseInputView: View {

    // MARK: - Public API

    var title: String
    @Binding var phrase: String
    var onSubmit: () -> Void
    /// Monotonically incrementing token; when it changes, the underlying
    /// UITextView becomes first responder. Default of `0` keeps the Stage 1
    /// preview behavior intact.
    var focusToken: Int = 0
    /// Monotonically incrementing token; when it changes the underlying
    /// UITextView selects the first case-insensitive occurrence of
    /// `selectionSubstring`. Defaults keep Stage 1 preview behavior intact.
    var selectionToken: Int = 0
    var selectionSubstring: String?

    // MARK: - Layout constants (mirroring the legacy DWRecoverTextView)

    private enum Layout {
        static let cornerRadius: CGFloat = 8
        static let textInset: CGFloat = 12
        static let lineSpacing: CGFloat = 10
        static let numberOfLines: Int = 5
        static let topPadding: CGFloat = 16
        static let titleToInputSpacing: CGFloat = 20
        static let bottomPadding: CGFloat = 12
        // Legacy ObjC layout pinned title/text view to full container width.
        static let horizontalPadding: CGFloat = 0
    }

    private var minInputHeight: CGFloat {
        SeedPhraseTextView.font.lineHeight * CGFloat(Layout.numberOfLines)
            + Layout.lineSpacing * CGFloat(max(Layout.numberOfLines - 1, 0))
            + Layout.textInset * 2
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(Font(UIFont.dw_font(forTextStyle: .title2)))
                .foregroundColor(Color(UIColor.dw_darkTitle()))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Layout.horizontalPadding)
                .padding(.top, Layout.topPadding)

            seedEditor
                .padding(.top, Layout.titleToInputSpacing)
                .padding(.bottom, Layout.bottomPadding)
                .padding(.horizontal, Layout.horizontalPadding)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color(UIColor.dw_secondaryBackground()))
    }

    private var seedEditor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .fill(Color(UIColor.dw_background()))

            SeedPhraseTextView(
                text: $phrase,
                onSubmit: onSubmit,
                textInset: Layout.textInset,
                lineSpacing: Layout.lineSpacing,
                focusToken: focusToken,
                selectionToken: selectionToken,
                selectionSubstring: selectionSubstring
            )
            .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        }
        .frame(minHeight: minInputHeight)
    }
}

// MARK: - UITextView bridge

private struct SeedPhraseTextView: UIViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var textInset: CGFloat
    var lineSpacing: CGFloat
    var focusToken: Int
    var selectionToken: Int
    var selectionSubstring: String?

    static let font: UIFont = .dw_font(forTextStyle: .body)

    private static func typingAttributes(lineSpacing: CGFloat) -> [NSAttributedString.Key: Any] {
        // Replicates the per-line spacing the legacy `DWRecoverTextView`
        // applied via its NSLayoutManagerDelegate, but does it through a
        // paragraph style so we don't have to opt into TextKit 1 fallback.
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.alignment = .center
        return [
            .font: font,
            .foregroundColor: UIColor.dw_dashBlue(),
            .paragraphStyle: paragraphStyle,
        ]
    }

    func makeUIView(context: Context) -> UITextView {
#if SEED_INPUT_DIAGNOSTICS
        RecoverSeedPhraseInputDebugLog.log("makeUIView/create")
#endif
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.font = Self.font
        textView.textColor = .dw_dashBlue()
        textView.tintColor = .dw_dashBlue()
        textView.textAlignment = .center
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.autocapitalizationType = .none
        textView.keyboardType = .default
        textView.returnKeyType = .done
        if #available(iOS 17.0, *) {
            textView.inlinePredictionType = .no
        }
        if #available(iOS 18.0, *) {
            textView.writingToolsBehavior = .none
        }
        textView.textContainerInset = UIEdgeInsets(
            top: textInset, left: textInset, bottom: textInset, right: textInset
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.typingAttributes = Self.typingAttributes(lineSpacing: lineSpacing)
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.recordUpdateUIViewEvent()

        // Keep the coordinator's callback fresh so we never hold a stale
        // closure across SwiftUI re-renders.
        context.coordinator.onSubmit = onSubmit

        // Avoid a feedback loop: only push the binding into UIKit when the
        // external value diverges from what the user has typed. When we do,
        // re-render through an attributed string so paragraph spacing /
        // alignment carry over to externally-pasted content.
        if uiView.text != text {
#if SEED_INPUT_DIAGNOSTICS
            RecoverSeedPhraseInputDebugLog.log(
                "external phrase set: chars=\(text.count), words=\((text as NSString).wordsCount)"
            )
#endif
            uiView.attributedText = NSAttributedString(
                string: text,
                attributes: Self.typingAttributes(lineSpacing: lineSpacing)
            )
        }

        // Externally-driven focus. Compare against the last applied token so
        // we only call becomeFirstResponder once per increment.
        if focusToken != context.coordinator.lastFocusToken {
            context.coordinator.lastFocusToken = focusToken
#if SEED_INPUT_DIAGNOSTICS
            RecoverSeedPhraseInputDebugLog.log("focus token received: \(focusToken)")
#endif
            // Defer to the next runloop to avoid focusing during layout.
            DispatchQueue.main.async { [weak uiView] in
                guard let uiView else { return }
                if !uiView.isFirstResponder {
                    let becameFirstResponder = uiView.becomeFirstResponder()
#if SEED_INPUT_DIAGNOSTICS
                    RecoverSeedPhraseInputDebugLog.log(
                        "becomeFirstResponder result=\(becameFirstResponder)"
                    )
#endif
                }
                else {
#if SEED_INPUT_DIAGNOSTICS
                    RecoverSeedPhraseInputDebugLog.log("becomeFirstResponder skipped (already first responder)")
#endif
                }
            }
        }

        // Externally-driven selection. Mirrors the legacy
        // `textView.selectedRange = [text.lowercaseString rangeOfString:word]`
        // behavior used to highlight an invalid seed word before showing the
        // alert.
        if selectionToken != context.coordinator.lastSelectionToken {
            context.coordinator.lastSelectionToken = selectionToken
            if let substring = selectionSubstring, !substring.isEmpty {
#if SEED_INPUT_DIAGNOSTICS
                RecoverSeedPhraseInputDebugLog.log(
                    "external selection request: token=\(selectionToken), substringLength=\(substring.count)"
                )
#endif
                let textNS = (uiView.text ?? "") as NSString
                let loweredText = textNS.lowercased as NSString
                let loweredSubstring = substring.lowercased()
                let range = loweredText.range(of: loweredSubstring)
                if range.location != NSNotFound {
                    DispatchQueue.main.async { [weak uiView] in
                        uiView?.selectedRange = range
                    }
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        var onSubmit: () -> Void
        var lastFocusToken: Int = 0
        var lastSelectionToken: Int = 0
        private var updateUIViewWindowStart: TimeInterval = Date().timeIntervalSince1970
        private var updateUIViewCountInWindow: Int = 0

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self._text = text
            self.onSubmit = onSubmit
        }

        func recordUpdateUIViewEvent() {
            let now = Date().timeIntervalSince1970
            if now - updateUIViewWindowStart > 1.0 {
                updateUIViewWindowStart = now
                updateUIViewCountInWindow = 0
            }

            updateUIViewCountInWindow += 1
#if SEED_INPUT_DIAGNOSTICS
            if updateUIViewCountInWindow == 40 {
                RecoverSeedPhraseInputDebugLog.log(
                    "high updateUIView churn: ~\(updateUIViewCountInWindow) updates in <1s"
                )
            }
#endif
        }

        func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
#if SEED_INPUT_DIAGNOSTICS
            RecoverSeedPhraseInputDebugLog.log("textViewShouldBeginEditing")
#endif
            return true
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
#if SEED_INPUT_DIAGNOSTICS
            RecoverSeedPhraseInputDebugLog.log("textViewDidBeginEditing")
#endif
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
#if SEED_INPUT_DIAGNOSTICS
            let updatedText = textView.text ?? ""
            RecoverSeedPhraseInputDebugLog.log(
                "textViewDidChange: chars=\(updatedText.count), words=\((updatedText as NSString).wordsCount)"
            )
#endif
        }

        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText replacement: String) -> Bool {
#if SEED_INPUT_DIAGNOSTICS
            RecoverSeedPhraseInputDebugLog.log(
                "shouldChangeTextInRange: rangeLength=\(range.length), replacementLength=\(replacement.count), isNewline=\(replacement == "\n")"
            )
#endif
            // Match the legacy behaviour where the Return key triggers
            // submission instead of being inserted into the phrase.
            if replacement == "\n" {
                onSubmit()
                return false
            }
            return true
        }
    }
}

// MARK: - Previews

private struct RecoverSeedPhraseInputPreviewHost: View {
    @State var phrase: String

    var body: some View {
        RecoverSeedPhraseInputView(
            title: NSLocalizedString("Enter Recovery Phrase", comment: ""),
            phrase: $phrase,
            onSubmit: {
                print("preview onSubmit, phrase=\(phrase)")
            }
        )
    }
}

#Preview("Empty") {
    RecoverSeedPhraseInputPreviewHost(phrase: "")
}

#Preview("Multi-word") {
    RecoverSeedPhraseInputPreviewHost(
        phrase: "alpha bravo charlie delta echo foxtrot"
    )
}

#Preview("Long wrapping") {
    RecoverSeedPhraseInputPreviewHost(
        phrase: "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee zulu"
    )
}

#Preview("Prefilled 12 words") {
    RecoverSeedPhraseInputPreviewHost(
        phrase: "abandon ability able about above absent absorb abstract absurd abuse access accident"
    )
}

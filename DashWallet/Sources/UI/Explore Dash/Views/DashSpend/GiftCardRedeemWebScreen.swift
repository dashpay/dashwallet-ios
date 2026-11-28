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

import SwiftUI
import WebKit
import DashUIKit

/// In-app browser for a CTX gift card's redeem link, with the challenge code kept above the page.
struct GiftCardRedeemWebScreen: View {
    @StateObject private var viewModel: GiftCardRedeemWebViewModel
    @Environment(\.dismiss) private var dismiss
    private let merchantName: String
    private let challenge: String?
    private let onCopyChallenge: (String) -> Void

    init(
        link: String,
        merchantName: String,
        challenge: String?,
        onCopyChallenge: @escaping (String) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: GiftCardRedeemWebViewModel(link: link, ctxBaseURL: CTXConstants.baseURI)
        )
        self.merchantName = merchantName
        self.challenge = challenge
        self.onCopyChallenge = onCopyChallenge
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            pageNotice

            if let challenge {
                challengeBanner(challenge)
            }

            progressBar
            content
        }
        .background(Color.dash.primaryBackground.ignoresSafeArea())
        .overlay {
            RedeemPrivacyCover()
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onAppear {
            viewModel.loadIfNeeded()
        }
        .onDisappear {
            viewModel.tearDown()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // Both are drawn above the privacy cover.
            viewModel.dismissScriptDialog()
            GiftCardSheetFeedback.hideNotice()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // The root controller raises the lock screen from this same notification; look once it has.
            DispatchQueue.main.async {
                if WalletLifecycleOverlayPresenter.shared.lockScreenVisible {
                    dismiss()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            // The app lock can be off or not yet due, so leaving the app or locking the device ends the
            // session. A system alert, Control Centre or the app switcher only makes the app inactive.
            dismiss()
        }
    }

    private var header: some View {
        ZStack {
            Text(merchantName)
                .font(.subheadMedium)
                .foregroundColor(.dash.primaryText)
                .lineLimit(1)
                .padding(.horizontal, 104)

            HStack(spacing: 0) {
                if viewModel.canGoBack {
                    headerButton(
                        systemImage: "chevron.backward",
                        label: String(localized: "Back", comment: "Accessibility"),
                        action: { viewModel.goBack() }
                    )
                }

                Spacer()

                headerButton(
                    systemImage: "safari",
                    label: String(localized: "Open in browser", comment: "DashSpend"),
                    action: { viewModel.openInBrowser() }
                )

                headerButton(
                    systemImage: "xmark",
                    label: String(localized: "Close", comment: "Accessibility"),
                    action: { dismiss() }
                )
            }
            .padding(.horizontal, 8)
        }
        .frame(minHeight: 44)
    }

    private func headerButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundColor(.dash.primaryText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private var pageNotice: some View {
        VStack(spacing: 4) {
            Text(viewModel.host ?? " ")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.dash.primaryText)
                .lineLimit(1)
                // The end of a host is the part that says who owns it.
                .truncationMode(.head)
                .accessibilityHidden(viewModel.host == nil)

            Text(String(
                localized: "External website. Parts of this page may come from other sites. Dash will never ask for your wallet PIN or recovery phrase here.",
                comment: "DashSpend"
            ))
            .font(.footnote)
            .foregroundColor(.dash.secondaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private func challengeBanner(_ challenge: String) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Challenge code", comment: "DashSpend"))
                    .font(.caption)
                    .foregroundColor(.dash.tertiaryText)

                Text(challenge)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundColor(.dash.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DashButton(
                text: String(localized: "Copy", comment: ""),
                style: .tintedBlue,
                size: .small,
                stretch: false,
                action: { onCopyChallenge(challenge) }
            )
            .accessibilityLabel(String(localized: "Copy challenge code", comment: "DashSpend"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Color.dash.secondaryBackground)
        .clipShape(.rect(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }

    private var progressBar: some View {
        ZStack {
            if !viewModel.hasError && viewModel.progress < 1 {
                SwiftUI.ProgressView(value: viewModel.progress)
                    .progressViewStyle(.linear)
                    .tint(.dash.blue)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 4)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.hasError {
            errorState
        } else if let webView = viewModel.webView {
            RedeemWebView(webView: webView, onTouch: { viewModel.userDidTouchPage() })
                .id(ObjectIdentifier(webView))
                .ignoresSafeArea(.keyboard)
        } else {
            Spacer()
        }
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Text(String(localized: "This page could not be loaded.", comment: "DashSpend"))
                .font(.subhead)
                .foregroundColor(.dash.primaryText)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            DashButton(
                text: String(localized: "Try again", comment: ""),
                style: .filledBlue,
                action: { viewModel.load() }
            )

            DashButton(
                text: String(localized: "Open in browser", comment: "DashSpend"),
                style: .plain,
                action: { viewModel.openInBrowser() }
            )
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RedeemWebView: UIViewRepresentable {
    let webView: WKWebView
    let onTouch: () -> Void

    func makeUIView(context: Context) -> RedeemWebContainerView {
        RedeemWebContainerView(webView: webView, onTouch: onTouch)
    }

    func updateUIView(_ uiView: RedeemWebContainerView, context: Context) { }
}

private final class RedeemWebContainerView: UIView {
    private let onTouch: () -> Void

    init(webView: WKWebView, onTouch: @escaping () -> Void) {
        self.onTouch = onTouch
        super.init(frame: .zero)
        backgroundColor = .systemBackground

        webView.frame = bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if event?.type == .touches {
            onTouch()
        }
        return super.hitTest(point, with: event)
    }
}

/// Hides the whole screen while the app is inactive, which is when the app switcher snapshot is taken.
private struct RedeemPrivacyCover: UIViewRepresentable {
    func makeUIView(context: Context) -> RedeemPrivacyCoverView {
        RedeemPrivacyCoverView()
    }

    func updateUIView(_ uiView: RedeemPrivacyCoverView, context: Context) { }
}

private final class RedeemPrivacyCoverView: UIView {
    private let cover = UIView()

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false

        cover.backgroundColor = .systemBackground
        cover.frame = bounds
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.isHidden = UIApplication.shared.applicationState == .active
        addSubview(cover)

        // The cover is set here, not through SwiftUI state, so it is in place before the snapshot.
        let center = NotificationCenter.default
        center.addObserver(self,
                           selector: #selector(hideScreen),
                           name: UIApplication.willResignActiveNotification,
                           object: nil)
        center.addObserver(self,
                           selector: #selector(showScreen),
                           name: UIApplication.didBecomeActiveNotification,
                           object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func hideScreen() {
        cover.isHidden = false
    }

    @objc
    private func showScreen() {
        cover.isHidden = true
    }
}

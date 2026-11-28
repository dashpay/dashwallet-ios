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

import Combine
import UIKit
import WebKit

@MainActor
final class GiftCardRedeemWebViewModel: NSObject, ObservableObject {
    private static let maxScriptDialogs = 3

    @Published private(set) var webView: WKWebView?
    @Published private(set) var host: String?
    @Published private(set) var progress: Double = 0
    @Published private(set) var hasError = false
    @Published private(set) var canGoBack = false

    private let link: String
    private let ctxBaseURL: String
    private var isAwaitingFirstRequest = false
    private var hasCommittedPage = false
    private var committedNavigation: WKNavigation?
    private var scriptDialogCount = 0
    private var blockedNoticeShown = false
    private var observations = Set<AnyCancellable>()
    private var scriptDialog: (alert: UIAlertController, reply: ScriptDialogReply)?

    /// WebKit lets an app refuse a page's file upload panel only from iOS 18.4; before that the link
    /// opens in the system browser.
    static var canRefuseUploads: Bool {
        if #available(iOS 18.4, *) {
            return true
        }
        return false
    }

    init(link: String, ctxBaseURL: String) {
        self.link = link
        self.ctxBaseURL = ctxBaseURL
    }

    func loadIfNeeded() {
        if webView == nil && !hasError {
            load()
        }
    }

    /// Starts from the original link in a new web view, which also starts from an empty data store.
    func load() {
        discardWebView()
        host = nil
        hasCommittedPage = false
        scriptDialogCount = 0
        blockedNoticeShown = false
        progress = 0

        guard let url = RedeemLinkPolicy.inAppURL(link, ctxBaseURL: ctxBaseURL) else {
            hasError = true
            return
        }

        let view = makeWebView()
        hasError = false
        isAwaitingFirstRequest = true
        webView = view
        view.publisher(for: \.estimatedProgress)
            .sink { [weak self] progress in
                self?.progress = progress
            }
            .store(in: &observations)
        view.publisher(for: \.canGoBack)
            .sink { [weak self] canGoBack in
                self?.canGoBack = canGoBack
            }
            .store(in: &observations)
        view.load(URLRequest(url: url))
    }

    func tearDown() {
        discardWebView()
    }

    /// Only a touch on the page lifts the dialog and notice limits, so a page cannot reset them by navigating.
    func userDidTouchPage() {
        scriptDialogCount = 0
        blockedNoticeShown = false
    }

    func goBack() {
        webView?.goBack()
    }

    func openInBrowser() {
        guard let url = RedeemLinkPolicy.externalURL(link, ctxBaseURL: ctxBaseURL) else {
            showBlockedNotice()
            return
        }
        UIApplication.shared.open(url)
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.denyGeolocationScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsLinkPreview = false
        view.allowsBackForwardNavigationGestures = true
        view.navigationDelegate = self
        view.uiDelegate = self
        return view
    }

    // WKUIDelegate has no public hook to deny a page's location request, so the page API is replaced.
    // WebKit does not run user scripts in a frame's initial empty document, so this is best effort.
    private static let denyGeolocationScript = """
    (function () {
        var proto = window.Geolocation && window.Geolocation.prototype;
        if (!proto) { return; }
        function deny(success, failure) {
            if (typeof failure !== 'function') { return; }
            setTimeout(function () {
                failure({ code: 1, message: 'Location is not available', PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3 });
            }, 0);
        }
        function replace(name, value) {
            try {
                Object.defineProperty(proto, name, { value: value, writable: false, configurable: false });
            } catch (e) {}
        }
        replace('getCurrentPosition', function (success, failure) { deny(success, failure); });
        replace('watchPosition', function (success, failure) { deny(success, failure); return 0; });
        replace('clearWatch', function () {});
    })();
    """

    /// Answers a showing page dialog as declined and takes it down.
    func dismissScriptDialog() {
        if let scriptDialog {
            scriptDialog.reply.send(false)
            scriptDialog.alert.dismiss(animated: false)
        }
        scriptDialog = nil
    }

    private func discardWebView() {
        dismissScriptDialog()
        observations.removeAll()
        canGoBack = false
        committedNavigation = nil

        if let webView {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
        }
        webView = nil
    }

    private func fail() {
        discardWebView()
        hasError = true
    }

    private func policy(for action: WKNavigationAction) -> WKNavigationActionPolicy {
        let url = action.request.url
        // A request for a new window has no target frame; it would load in this view's main frame.
        let isMainFrame = action.targetFrame?.isMainFrame ?? true

        if isMainFrame && isAwaitingFirstRequest {
            isAwaitingFirstRequest = false
            // WebKit parses the link again; what it is about to request must still be the CTX redeem link.
            guard RedeemLinkPolicy.canOpenInApp(url?.absoluteString, ctxBaseURL: ctxBaseURL) else {
                fail()
                return .cancel
            }
        }

        if action.shouldPerformDownload {
            refuseDownload()
            return .cancel
        }

        if RedeemLinkPolicy.isAllowedNavigation(url?.absoluteString, isMainFrame: isMainFrame) {
            return .allow
        }

        if isMainFrame {
            // A script's click counts as link activation too, so nothing is handed to another app from here.
            if action.navigationType == .linkActivated {
                showBlockedNoticeOnce()
            }
            // A redirect chain that ends here leaves a blank view.
            if !hasCommittedPage {
                fail()
            }
        }
        return .cancel
    }

    private func refuseDownload() {
        if !hasCommittedPage {
            fail()
        } else {
            showBlockedNoticeOnce()
        }
    }

    private func showBlockedNoticeOnce() {
        guard !blockedNoticeShown else { return }
        blockedNoticeShown = true
        showBlockedNotice()
    }

    private func showBlockedNotice() {
        GiftCardSheetFeedback.showBlockedLinkNotice()
    }

    // Never the top page's host: a frame without a host of its own must not speak in that page's name.
    private func scriptDialogTitle(for frame: WKFrameInfo) -> String {
        let frameHost = frame.securityOrigin.host
        return frameHost.isEmpty ? String(localized: "This page says", comment: "DashSpend") : frameHost
    }

    private func showScriptDialog(in webView: WKWebView,
                                  message: String,
                                  frame: WKFrameInfo,
                                  canDecline: Bool,
                                  completion: @escaping (Bool) -> Void) {
        let reply = ScriptDialogReply(completion)

        guard webView === self.webView,
              scriptDialog == nil,
              scriptDialogCount < Self.maxScriptDialogs,
              UIApplication.shared.applicationState == .active,
              let presenter = webView.window?.rootViewController?.topController() else {
            reply.send(false)
            return
        }
        scriptDialogCount += 1

        let alert = UIAlertController(
            title: scriptDialogTitle(for: frame),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "OK", comment: ""), style: .default) { [weak self] _ in
            self?.scriptDialog = nil
            reply.send(true)
        })
        if canDecline {
            alert.addAction(UIAlertAction(title: String(localized: "Cancel", comment: ""), style: .cancel) { [weak self] _ in
                self?.scriptDialog = nil
                reply.send(false)
            })
        }
        scriptDialog = (alert, reply)
        presenter.present(alert, animated: true)
    }
}

extension GiftCardRedeemWebViewModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        decisionHandler(webView === self.webView ? policy(for: navigationAction) : .cancel)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        guard webView === self.webView else {
            decisionHandler(.cancel)
            return
        }

        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?
            .lowercased()
        let isAttachment = disposition?.hasPrefix("attachment") ?? false

        if navigationResponse.canShowMIMEType && !isAttachment {
            decisionHandler(.allow)
        } else {
            if navigationResponse.isForMainFrame {
                refuseDownload()
            }
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        let url = webView.url?.absoluteString

        host = RedeemLinkPolicy.displayHost(url)
        // Not every navigation asks for a policy decision first, so check what was committed too.
        if RedeemLinkPolicy.isAllowedNavigation(url, isMainFrame: true) {
            hasCommittedPage = true
            committedNavigation = navigation
        } else {
            fail()
        }
    }

    // Before the first commit any failure would leave a blank view, whatever its cause: a navigation this
    // class cancels there has already discarded the web view, so what arrives here came from WebKit.
    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        guard webView === self.webView else { return }

        if RedeemLinkPolicy.isFatalLoadFailure(error, stage: .beforeCommit(hasCommittedPage: hasCommittedPage)) {
            fail()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView else { return }
        let isShowingPage = navigation != nil && navigation === committedNavigation

        if RedeemLinkPolicy.isFatalLoadFailure(error, stage: .afterCommit(isShowingPage: isShowingPage)) {
            fail()
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        fail()
    }

    // Default handling rejects a server whose certificate does not validate.
    func webView(_ webView: WKWebView,
                 didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }
}

extension GiftCardRedeemWebViewModel: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = navigationAction.request.url?.absoluteString

        if webView === self.webView, RedeemLinkPolicy.isAllowedNavigation(url, isMainFrame: true) {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor @Sendable () -> Void) {
        showScriptDialog(in: webView, message: message, frame: frame, canDecline: false) { _ in
            completionHandler()
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        showScriptDialog(in: webView, message: message, frame: frame, canDecline: true) { accepted in
            completionHandler(accepted)
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
        completionHandler(nil)
    }

    @available(iOS 18.4, *)
    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        completionHandler(nil)
    }

    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }

    func webView(_ webView: WKWebView,
                 requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }
}

/// WebKit raises an exception when a dialog's completion handler is released without being called.
private final class ScriptDialogReply {
    private var completion: ((Bool) -> Void)?

    init(_ completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    deinit {
        completion?(false)
    }

    func send(_ accepted: Bool) {
        completion?(accepted)
        completion = nil
    }
}

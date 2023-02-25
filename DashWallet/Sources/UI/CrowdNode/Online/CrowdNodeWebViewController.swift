//
//  Created by Andrei Ashikhmin
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

import Combine
import UIKit
import WebKit

private let kSignupSuffix = "&view=signup-only"
private let kCallbackSuffix = "callback"

class CrowdNodeWebViewController: BaseViewController {
    private var cancellableBag = Set<AnyCancellable>()
    private let viewModel = CrowdNodeModel.shared
    private var webView: WKWebView!
    private var url: URL!
    
    // MARK: New Online Account
    private var email: String? = nil
    private let loginPrefix = CrowdNode.loginUrl
    private let accountPrefix = CrowdNode.baseUrl
    private var previousUrl = ""

    @objc
    static func controller(url: URL, email: String? = nil) -> CrowdNodeWebViewController {
        let vc = CrowdNodeWebViewController()
        vc.url = url
        vc.email = email
        return vc
    }

    override func viewDidDisappear(_ animated: Bool) {
        viewModel.cancelLinkingOnlineAccount()
    }

    override func loadView() {
        super.loadView()
        webView = WKWebView(frame: .zero)
        webView.navigationDelegate = self
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .dw_secondaryBackground()

        navigationItem.title = NSLocalizedString("Log in to CrowdNode", comment: "CrowdNode WebView")
        let urlRequest = URLRequest(url: url)
        webView.load(urlRequest)
        configureObservers()
    }

    override func viewWillDisappear(_ animated: Bool) {
        WKWebView.cleanCrowdNodeCache()
    }

    private func configureObservers() {
        viewModel.$signUpState
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if state == .linkedOnline {
                    self?.navigationController?.replaceLast(3, with: CrowdNodePortalController.controller())
                }
            }
            .store(in: &cancellableBag)
        
        viewModel.$onlineAccountState
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if state == .done {
                    self?.navigationController?.popViewController(animated: true)
                }
            }
            .store(in: &cancellableBag)
        
        viewModel.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                if error != nil {
                    self?.navigationController?.popViewController(animated: true)
                }
            }
            .store(in: &cancellableBag)
    }
}

extension CrowdNodeWebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {

        if let email = email, let url = navigationAction.request.url?.absoluteString {
            let fullSuffix = "\(kSignupSuffix)&loginHint=\(email)"
            
            if (url.hasPrefix(loginPrefix) && !url.hasSuffix(fullSuffix) && !url.hasSuffix(kCallbackSuffix)) {
                let redirectUrl = "\(url)\(fullSuffix)"
                let urlRequest = URLRequest(url: URL(string: redirectUrl)!)
                webView.load(urlRequest)
                previousUrl = url
                
                return (WKNavigationActionPolicy.cancel, preferences)
            } else if (previousUrl.hasPrefix(loginPrefix) && url.hasPrefix(accountPrefix)) {
                // Successful signup
                viewModel.finishSignUpToOnlineAccount()
            }
            
            previousUrl = url
        }
        
        return (WKNavigationActionPolicy.allow, preferences)
    }
}

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

class CrowdNodeWebViewController: UIViewController {
    private var cancellableBag = Set<AnyCancellable>()
    private let viewModel = CrowdNodeModel.shared
    private var webView: WKWebView!
    private var url: URL!

    @objc
    static func controller(url: URL) -> CrowdNodeWebViewController {
        let vc = CrowdNodeWebViewController()
        vc.url = url
        return vc
    }

    override func viewDidDisappear(_ animated: Bool) {
        viewModel.cancelLinkingOnlineAccount()
    }

    override func loadView() {
        super.loadView()
        webView = WKWebView(frame: .zero)
        view = webView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
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
    }
}

//
//  BRBrowserViewController.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 6/23/17.
//  Copyright © 2017 Aaron Voisine. All rights reserved.
//

import Foundation
import UIKit
import WebKit

@available(iOS 8.0, *)
fileprivate class BRBrowserViewControllerInternal: UIViewController, WKNavigationDelegate {
    var request: URLRequest?
    fileprivate let webView = WKWebView()
    fileprivate let toolbarContainerView = UIView()
    fileprivate let toolbarView = UIToolbar()
    fileprivate let progressView = UIProgressView()
    fileprivate let refreshButtonItem = UIBarButtonItem(
        barButtonSystemItem: UIBarButtonSystemItem.refresh, target: self,
        action: #selector(BRBrowserViewControllerInternal.refresh))
    fileprivate var stopButtonItem = UIBarButtonItem(
        barButtonSystemItem: UIBarButtonSystemItem.stop, target: self,
        action: #selector(BRBrowserViewControllerInternal.stop))
    fileprivate var flexibleSpace = UIBarButtonItem(
        barButtonSystemItem: UIBarButtonSystemItem.flexibleSpace, target: nil, action: nil)
    fileprivate var backButtonItem = UIBarButtonItem(
        title: "\u{25C0}\u{FE0E}", style: UIBarButtonItemStyle.plain, target: self,
        action: #selector(BRBrowserViewControllerInternal.goBack))
    fileprivate var forwardButtonItem = UIBarButtonItem(
        title: "\u{25B6}\u{FE0E}", style: UIBarButtonItemStyle.plain, target: self,
        action: #selector(BRBrowserViewControllerInternal.goForward))
    
    open override var edgesForExtendedLayout: UIRectEdge {
        get {
            return UIRectEdge(rawValue: super.edgesForExtendedLayout.rawValue ^ UIRectEdge.bottom.rawValue)
        }
        set {
            super.edgesForExtendedLayout = newValue
        }
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        // progress view
        progressView.alpha = 0
        progressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressView)
        view.addConstraints(NSLayoutConstraint.constraints(
            withVisualFormat: "|-0-[progressView]-0-|", options: [], metrics: nil,
            views: ["progressView": progressView]))
        view.addConstraints(NSLayoutConstraint.constraints(
            withVisualFormat: "V:|[topGuide]-0-[progressView(2)]", options: [], metrics: nil,
            views: ["progressView": progressView, "topGuide": self.topLayoutGuide]))
        
        // toolbar view 
        view.addSubview(toolbarContainerView)
        self.view.addSubview(toolbarContainerView)
        self.view.addConstraints(NSLayoutConstraint.constraints(
            withVisualFormat: "|-0-[toolbarContainer]-0-|", options: [], metrics: nil,
            views: ["toolbarContainer": toolbarContainerView]))
        self.view.addConstraints(NSLayoutConstraint.constraints(
            withVisualFormat: "V:[toolbarContainer]-0-|", options: [], metrics: nil,
            views: ["toolbarContainer": toolbarContainerView]))
        toolbarContainerView.addConstraint(NSLayoutConstraint(
            item: toolbarContainerView, attribute: .height, relatedBy: .equal, toItem: nil,
            attribute: .notAnAttribute, multiplier: 1, constant: 44))
        
        toolbarView.isTranslucent = true
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.items = [backButtonItem, forwardButtonItem, flexibleSpace, refreshButtonItem]
        toolbarContainerView.translatesAutoresizingMaskIntoConstraints = false
        toolbarContainerView.addSubview(toolbarView)
        toolbarContainerView.addConstraints(NSLayoutConstraint.constraints(
            withVisualFormat: "|-0-[toolbar]-0-|", options: [], metrics: nil, views: ["toolbar": toolbarView]))
        toolbarContainerView.addConstraints(NSLayoutConstraint.constraints(
            withVisualFormat: "V:|-0-[toolbar]-0-|", options: [], metrics: nil, views: ["toolbar": toolbarView]))
        
        // webview
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        view.addConstraints(NSLayoutConstraint.constraints(
            withVisualFormat: "|-0-[webView]-0-|", options: [], metrics: nil,
            views: ["webView": webView as WKWebView]))
        view.addConstraints(NSLayoutConstraint.constraints(
            withVisualFormat: "V:|[topGuide]-0-[webView]-0-[toolbarContainer]|", options: [], metrics: nil,
            views: ["webView": webView, "toolbarContainer": toolbarContainerView, "topGuide": self.topLayoutGuide]))
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        webView.addObserver(self, forKeyPath: "estimatedProgress", options: .new, context: nil)
        webView.addObserver(self, forKeyPath: "title", options: .new, context: nil)
        webView.addObserver(self, forKeyPath: "loading", options: .new, context: nil)
        print("[BRBrowserViewController viewWillAppear request = \(String(describing: request))")
        if let request = request {
            _ = webView.load(request)
        }
        
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        webView.removeObserver(self, forKeyPath: "estimatedProgress")
        webView.removeObserver(self, forKeyPath: "title")
        webView.removeObserver(self, forKeyPath: "loading")
    }
    
    open override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                   change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let keyPath = keyPath else { return }
        switch keyPath {
        case "estimatedProgress":
            if let newValue = change?[NSKeyValueChangeKey.newKey] as? NSNumber {
                progressChanged(newValue)
            }
        case "title":
            print("[BRBrowserViewController] title changed \(String(describing: webView.title))")
            self.navigationItem.title = webView.title
        case "loading":
            if let val = change?[NSKeyValueChangeKey.newKey] as? Bool {
                print("[BRBrowserViewController] loading changed \(val)")
                if !val {
                    showLoading(false)
                    backForwardListsChanged()
                }
            }
        default:
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    fileprivate func progressChanged(_ newValue: NSNumber) {
        print("[BRBrowserViewController] progress changed new value = \(newValue)")
        progressView.progress = newValue.floatValue
        if progressView.progress == 1 {
            progressView.progress = 0
            UIView.animate(withDuration: 0.2, animations: {
                self.progressView.alpha = 0
            })
        } else if progressView.alpha == 0 {
            UIView.animate(withDuration: 0.2, animations: {
                self.progressView.alpha = 1
            })
        }
    }
    
    fileprivate func showLoading(_ isLoading: Bool) {
        print("[BRBrowserViewController] showLoading \(isLoading)")
        if isLoading {
            self.toolbarView.items = [backButtonItem, forwardButtonItem, flexibleSpace, stopButtonItem];
        } else {
            self.toolbarView.items = [backButtonItem, forwardButtonItem, flexibleSpace, refreshButtonItem];
        }
    }
    
    fileprivate func showError(_ errString: String) {
        let alertView = UIAlertController(title: "Error", message: errString, preferredStyle: .alert)
        alertView.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        self.present(alertView, animated: true, completion: nil)
    }
    
    fileprivate func backForwardListsChanged() {
        // enable forward/back buttons
        backButtonItem.isEnabled = webView.canGoBack
        forwardButtonItem.isEnabled = webView.canGoForward
    }
    
    func goBack() {
        print("[BRBrowserViewController] go back")
        webView.goBack()
    }
    
    func goForward() {
        print("[BRBrowserViewController] go forward")
        webView.goForward()
    }
    
    func refresh() {
        print("[BRBrowserViewController] go refresh")
        webView.reload()
    }
    
    func stop() {
        print("[BRBrowserViewController] stop loading")
        webView.stopLoading()
    }
    
    // MARK: - WKNavigationDelegate 
    open func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        print("[BRBrowserViewController] webView didCommit navigation = \(navigation)")
    }
    
    open func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("[BRBrowserViewController] webView didFinish navigation = \(navigation)")
    }
    
    open func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        print("[BRBrowserViewController] webViewContentProcessDidTerminate")
    }
    
    open func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[BRBrowserViewController] webView didFail navigation = \(navigation) error = \(error)")
        showLoading(false)
        showError(error.localizedDescription)
    }
    
    open func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("[BRBrowserViewController] webView didFailProvisionalNavigation navigation = \(navigation) error = \(error)")
        showLoading(false)
        showError(error.localizedDescription)
    }
    
    open func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        print("[BRBrowserViewController] webView didStartProfisionalNavigation navigation = \(navigation)")
        showLoading(true)
    }
}

@available(iOS 8.0, *)
open class BRBrowserViewController: UINavigationController {
    var onDone: (() -> Void)?
    
    fileprivate let browser = BRBrowserViewControllerInternal()
    
    init() {
        super.init(navigationBarClass: UINavigationBar.self, toolbarClass: UIToolbar.self)
        self.viewControllers = [browser]
        browser.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(BRBrowserViewController.done))
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    func load(_ request: URLRequest) {
        print("[BRBrowserViewController] load request = \(request)")
        browser.request = request
    }
    
    @objc private func done(target: UIControl) {
        print("[BRBrowserViewController] done")
        self.dismiss(animated: true) { 
            if let onDone = self.onDone {
                onDone()
            }
        }
    }
}

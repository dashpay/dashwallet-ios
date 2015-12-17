//
//  BRWebViewController.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 12/10/15.
//  Copyright © 2015 Aaron Voisine. All rights reserved.
//

import Foundation
import UIKit
import WebKit

    
@available(iOS 9.0, *)
@objc public class BRWebViewController : UIViewController, WKScriptMessageHandler, WKNavigationDelegate {
    var wkProcessPool: WKProcessPool
    var webView: WKWebView?
    var bundleName: String
    var wkContentController: WKUserContentController?
    
    init(bundleName name: String) {
        wkProcessPool = WKProcessPool()
        bundleName = name
        super.init(nibName: nil, bundle: nil)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func loadView() {
        wkContentController = WKUserContentController()
        
        wkContentController?.addScriptMessageHandler(self, name: "close")
        
        let config = WKWebViewConfiguration()
        config.processPool = wkProcessPool
        config.userContentController = wkContentController!
        config.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore()
        config.allowsInlineMediaPlayback = false
        config.allowsAirPlayForMediaPlayback = false
        config.requiresUserActionForMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = false
        
//        BRAPIClient.sharedClient.serveBundle("bread-buy", debugURL: "http://localhost:4200")
        BRAPIClient.sharedClient.serveBundle("bread-buy")
        let indexUrl = NSURL(string: "http://localhost:8888/index.html")!
        let request = NSURLRequest(URL: indexUrl)
        
        view = UIView(frame: CGRectZero)
        view.backgroundColor = UIColor(red:0.98, green:0.98, blue:0.98, alpha:1.0)
        
        webView = WKWebView(frame: CGRectZero, configuration: config)
        webView?.backgroundColor = UIColor(red:0.98, green:0.98, blue:0.98, alpha:1.0)
        webView?.navigationDelegate = self
        webView?.loadRequest(request)
        webView?.autoresizingMask = [UIViewAutoresizing.FlexibleHeight, UIViewAutoresizing.FlexibleWidth]
        view.addSubview(webView!)
        
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .Cancel, target: self, action: "done:")
    }
    
    override public func viewWillAppear(animated: Bool) {
        edgesForExtendedLayout = .All
    }
    
    private func closeNow() {
        dismissViewControllerAnimated(true, completion: nil)
    }
    
    public func preload() {
        _ = self.view // force webview loading
    }
    
    // MARK: WKScriptMessageHandler
    
    public func userContentController(userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        switch message.name {
        case "close":
            closeNow()
            break
        default:
            break
        }
    }
    
    // MARK: WKNavigationDelegate
    
    public func webView(webView: WKWebView, didFailNavigation navigation: WKNavigation!, withError error: NSError) {
        NSLog("did fail navigation \(error)")
    }
    
    public func webView(webView: WKWebView, didFinishNavigation navigation: WKNavigation!) {
        NSLog("did finish navigation \(navigation)")
    }
}


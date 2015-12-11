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
@objc public class BRWebViewController : UINavigationController {
    // public class func prepareBundle(name: String)
    // Downloads the most recent version of the bundle that you may later want to display. Call this at the beginning
    // of the application at a time when network utilization is low.
    
    var webController: UIViewController?
    var bundleName: String = ""
    
    convenience init(bundleName name: String) {
        self.init()
        webController = BRWebViewInternalController(bundleName: name)
        bundleName = name
        viewControllers = [webController!]
    }
    
    @available(iOS 9.0, *)
    class BRWebViewInternalController : UIViewController, WKScriptMessageHandler, WKNavigationDelegate {
        var wkProcessPool: WKProcessPool
        var webView: WKWebView?
        var bundleName: String
        var wkContentController: WKUserContentController?
        
        init(bundleName name: String) {
            wkProcessPool = WKProcessPool()
            bundleName = name
            super.init(nibName: nil, bundle: nil)
        }
        
        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func loadView() {
            wkContentController = WKUserContentController()
            
            let config = WKWebViewConfiguration()
            config.processPool = wkProcessPool
            config.userContentController = wkContentController!
            config.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore()
            config.allowsInlineMediaPlayback = false
            config.allowsAirPlayForMediaPlayback = false
            config.requiresUserActionForMediaPlayback = true
            config.allowsPictureInPictureMediaPlayback = false
            
            BRAPIClient.sharedClient.serveBundle(bundleName)
            let indexUrl = NSURL(string: "http://localhost:8888/index.html")!
            let request = NSURLRequest(URL: indexUrl)
            
            webView = WKWebView(frame: CGRectZero, configuration: config)
            webView?.navigationDelegate = self
            webView?.loadRequest(request)
            view = webView
            
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .Cancel, target: self, action: "done:")
        }
        
        func done(sender: UIBarButtonItem) {
            self.dismissViewControllerAnimated(true, completion: nil)
        }
        
        // MARK: WKScriptMessageHandler
        
        func userContentController(userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
            
        }
        
        // MARK: WKNavigationDelegate
        
        func webView(webView: WKWebView, didFailNavigation navigation: WKNavigation!, withError error: NSError) {
            NSLog("did fail navigation \(error)")
        }
        
        func webView(webView: WKWebView, didFinishNavigation navigation: WKNavigation!) {
            NSLog("did finish navigation \(navigation)")
        }
    }
}

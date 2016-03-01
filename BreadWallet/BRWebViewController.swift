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
@objc public class BRWebViewController : UIViewController {
    var wkProcessPool: WKProcessPool
    var webView: WKWebView?
    var bundleName: String
    var server = BRHTTPServer()
    var debugEndpoint: String?
    
    init(bundleName name: String) {
        wkProcessPool = WKProcessPool()
        bundleName = name
        super.init(nibName: nil, bundle: nil)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func loadView() {
        let config = WKWebViewConfiguration()
        config.processPool = wkProcessPool
        config.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore()
        config.allowsInlineMediaPlayback = false
        config.allowsAirPlayForMediaPlayback = false
        config.requiresUserActionForMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = false
        
        do {
            try server.start()
        } catch let e {
            print("\n\n\nSERVER ERROR! \(e)\n\n\n")
        }
        setupIntegrations()

        let indexUrl = NSURL(string: "http://localhost:8888/")!
        let request = NSURLRequest(URL: indexUrl)
        
        view = UIView(frame: CGRectZero)
        view.backgroundColor = UIColor(red:0.98, green:0.98, blue:0.98, alpha:1.0)
        
        webView = WKWebView(frame: CGRectZero, configuration: config)
        webView?.backgroundColor = UIColor(red:0.98, green:0.98, blue:0.98, alpha:1.0)
        webView?.loadRequest(request)
        webView?.autoresizingMask = [UIViewAutoresizing.FlexibleHeight, UIViewAutoresizing.FlexibleWidth]
        view.addSubview(webView!)
    }
    
    override public func viewWillAppear(animated: Bool) {
        edgesForExtendedLayout = .All
    }
    
    private func closeNow() {
        dismissViewControllerAnimated(true, completion: nil)
    }
    
    private func setupIntegrations() {
        // proxy api for signing and verification
        let apiProxy = BRAPIProxy(mountAt: "/_api", client: BRAPIClient.sharedClient)
        server.prependMiddleware(middleware: apiProxy)
        
        // http router for native functionality
        let router = BRHTTPRouter()
        server.prependMiddleware(middleware: router)
        
        // basic file server for static assets
        let fileMw = BRHTTPFileMiddleware(baseURL: BRAPIClient.bundleURL(bundleName))
        server.prependMiddleware(middleware: fileMw)
        
        // middleware to always return index.html for any unknown GET request (facilitates window.history style SPAs)
        let indexMw = BRHTTPIndexMiddleware(baseURL: fileMw.baseURL)
        server.prependMiddleware(middleware: indexMw)
        
        // geo plugin provides access to onboard geo location functionality
        router.plugin(BRGeoLocationPlugin())
        
        // wallet plugin provides access to the wallet
        router.plugin(BRWalletPlugin())
        
        // GET /_close closes the browser modal
        router.get("/_close") { (request, match) -> BRHTTPResponse in
            self.closeNow()
            return BRHTTPResponse(request: request, code: 204)
        }
        
        // enable debug if it is turned on
        if let debugUrl = debugEndpoint {
            let url = NSURL(string: debugUrl)
            fileMw.debugURL = url
            indexMw.debugURL = url
        }
    }
    
    public func preload() {
        _ = self.view // force webview loading
    }
    
    public func refresh() {
        webView?.reload()
    }
}

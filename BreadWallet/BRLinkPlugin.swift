//
//  BRLinkPlugin.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 3/10/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import Foundation

@objc class BRLinkPlugin: NSObject, BRHTTPRouterPlugin {
    func hook(router: BRHTTPRouter) {
        router.get("/_open_url") { (request, match) -> BRHTTPResponse in
            if let encodedUrls = request.query["url"] where encodedUrls.count == 1 {
                if let decodedUrl = encodedUrls[0].stringByRemovingPercentEncoding, url = NSURL(string: decodedUrl) {
                    print("[BRLinkPlugin] openURL \(decodedUrl)")
                    UIApplication.sharedApplication().openURL(url)
                    return BRHTTPResponse(request: request, code: 204)
                }
            }
            return BRHTTPResponse(request: request, code: 400)
        }
    }
}
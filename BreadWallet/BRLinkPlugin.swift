//
//  BRLinkPlugin.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 3/10/16.
//  Copyright (c) 2016 breadwallet LLC
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

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
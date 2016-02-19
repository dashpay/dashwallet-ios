//
//  BRHTTPIndexMiddleware.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 2/19/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import Foundation

// BRHTTPIndexMiddleware returns index.html to any GET requests - regardless of the URL being requestd
class BRHTTPIndexMiddleware: BRHTTPFileMiddleware {
    override func handle(request: BRHTTPRequest, next: (BRHTTPMiddlewareResponse) -> Void) {
        if request.method == "GET" {
            let newRequest = BRHTTPRequestImpl(fromRequest: request)
            newRequest.path = "/index.html"
            super.handle(newRequest, next: next)
        } else {
            next(BRHTTPMiddlewareResponse(request: request, response: nil))
        }
    }
}
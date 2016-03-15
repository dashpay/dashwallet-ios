//
//  BRWalletPlugin.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 2/18/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import Foundation

@objc class BRWalletPlugin: NSObject, BRHTTPRouterPlugin, BRWebSocketClient {
    var sockets = [String: BRWebSocket]()
    
    let manager = BRWalletManager.sharedInstance()!
    
    func hook(router: BRHTTPRouter) {
        router.websocket("/_wallet/_socket", client: self)
        
        router.get("/_wallet/info") { (request, match) -> BRHTTPResponse in
            return try BRHTTPResponse(request: request, code: 200, json: self.walletInfo())
        }
        
        router.get("/_wallet/format") { (request, match) -> BRHTTPResponse in
            if let amounts = request.query["amount"] where amounts.count > 0 {
                let amount = amounts[0]
                var intAmount: Int64 = 0
                if amount.containsString(".") { // assume full bitcoins
                    if let x = Float(amount) {
                        intAmount = Int64(x * 100000000.0)
                    }
                } else {
                    if let x = Int64(amount) {
                        intAmount = x
                    }
                }
                return try BRHTTPResponse(request: request, code: 200, json: self.currencyFormat(intAmount))
            } else {
                return BRHTTPResponse(request: request, code: 400)
            }
        }
    }
    
    // MARK: - basic wallet functions
    
    func walletInfo() -> [String: AnyObject] {
        var d = [String: AnyObject]()
        d["no_wallet"] = manager.noWallet
        d["watch_only"] = manager.watchOnly
        d["receive_address"] = manager.wallet?.receiveAddress
        return d
    }
    
    func currencyFormat(amount: Int64) -> [String: AnyObject] {
        var d = [String: AnyObject]()
        d["local_currency_amount"] = manager.localCurrencyStringForAmount(Int64(amount))
        d["currency_amount"] = manager.stringForAmount(amount)
        return d
    }
    
    // MARK: - socket handlers
    
    func socketDidConnect(socket: BRWebSocket) {
        print("WALLET CONNECT \(socket.id)")
        sockets[socket.id] = socket
    }
    
    func socketDidDisconnect(socket: BRWebSocket) {
        print("WALLET DISCONNECT \(socket.id)")
        sockets.removeValueForKey(socket.id)
    }
    
    func socket(socket: BRWebSocket, didReceiveText text: String) {
        print("WALLET RECV \(text)")
        socket.send(text)
    }
}
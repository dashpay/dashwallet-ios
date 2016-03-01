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
    }
    
    // MARK: - basic wallet functions
    
    func walletInfo() -> [String: AnyObject] {
        var d = [String: AnyObject]()
        d["no_wallet"] = manager.noWallet
        d["watch_only"] = manager.watchOnly
        d["receive_address"] = manager.wallet?.receiveAddress
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
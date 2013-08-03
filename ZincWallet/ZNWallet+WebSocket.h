//
//  ZNWallet+WebSocket.h
//  ZincWallet
//
//  Created by Aaron Voisine on 8/2/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNWallet.h"
#import "WebSocket.h"

@interface ZNWallet (WebSocket)<WebSocketDelegate>

- (void)openSocket;
- (void)closeSocket;
- (void)subscribeToAddresses:(NSArray *)addresses;

@end

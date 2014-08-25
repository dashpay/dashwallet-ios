//
//  BRPeerManager.h
//  BreadWallet
//
//  Created by Aaron Voisine on 10/6/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
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

#import <Foundation/Foundation.h>
#import "BRPeer.h"

#define BRPeerManagerSyncStartedNotification  @"BRPeerManagerSyncStartedNotification"
#define BRPeerManagerSyncFinishedNotification @"BRPeerManagerSyncFinishedNotification"
#define BRPeerManagerSyncFailedNotification   @"BRPeerManagerSyncFailedNotification"
#define BRPeerManagerTxStatusNotification     @"BRPeerManagerTxStatusNotification"

@class BRTransaction;

@interface BRPeerManager : NSObject <BRPeerDelegate, UIAlertViewDelegate>

@property (nonatomic, readonly) BOOL connected;
@property (nonatomic, readonly) uint32_t lastBlockHeight;
@property (nonatomic, readonly) uint32_t estimatedBlockHeight; // last block height reported by current download peer
@property (nonatomic, readonly) double syncProgress;
@property (nonatomic, readonly) NSUInteger peerCount; // number of connected peers

+ (instancetype)sharedInstance;

- (void)connect;
- (void)rescan;
- (void)publishTransaction:(BRTransaction *)transaction completion:(void (^)(NSError *error))completion;
- (NSUInteger)relayCountForTransaction:(NSData *)txHash; // number of connected peers that have relayed the transaction
- (NSTimeInterval)timestampForBlockHeight:(uint32_t)blockHeight; // seconds since reference date, 00:00:00 01/01/01 GMT

@end

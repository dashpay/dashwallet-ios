//
//  ZNBitcoin.h
//  ZincWallet
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
#import "ZNPeer.h"

@interface ZNPeerManager : NSObject<ZNPeerDelegate>

@property (nonatomic, readonly) BOOL connected;

// set this to the oldest block that might contain a wallet transaction to improve initial sync time
@property (nonatomic, assign) uint32_t earliestBlockHeight;

+ (instancetype)sharedInstance;

- (void)connect;
- (void)subscribeToAddresses:newaddresses;
- (void)publishTransaction:(ZNTransaction *)transaction completion:(void (^)(NSError *error))completion;

// Bitcoin nodes will only respond with a tx message in repsonse to a getdata if the tx exists, is valid, and is not yet
// included in a block. This method attempts a getdata to see if the given transaction meets these conditions.
- (void)verifyTransaction:(ZNTransaction *)transaction completion:(void (^)(BOOL verified))completion;

@end

//
//  ZNPeer.h
//  ZincWallet
//
//  Created by Aaron Voisine on 10/9/13.
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
#import "NSString+Base58.h" //BITCOIN_TESTNET is defined here

#if BITCOIN_TESTNET
#define STANDARD_PORT     18333
#else // BITCOIN_TESTNET
#define STANDARD_PORT     8333
#endif // BITCOIN_TESTNET

#define NODE_NETWORK      1

#define MSG_VERSION     @"version"
#define MSG_VERACK      @"verack"
#define MSG_ADDR        @"addr"
#define MSG_INV         @"inv"
#define MSG_GETDATA     @"getdata"
#define MSG_NOTFOUND    @"notfound"
#define MSG_GETBLOCKS   @"getblocks"
#define MSG_GETHEADERS  @"getheaders"
#define MSG_TX          @"tx"
#define MSG_BLOCK       @"block"
#define MSG_HEADERS     @"headers"
#define MSG_GETADDR     @"getaddr"
#define MSG_MEMPOOL     @"mempool"
#define MSG_CHECKORDER  @"checkorder"
#define MSG_SUBMITORDER @"submitorder"
#define MSG_REPLY       @"reply"
#define MSG_PING        @"ping"
#define MSG_PONG        @"pong"
#define MSG_FILTERLOAD  @"filterload"
#define MSG_FILTERADD   @"filteradd"
#define MSG_FILTERCLEAR @"filterclear"
#define MSG_MERKLEBLOCK @"merkleblock"
#define MSG_ALERT       @"alert"

@class ZNPeer, ZNTransaction;

@protocol ZNPeerDelegate<NSObject>
@required

- (void)peerConnected:(ZNPeer *)peer;
- (void)peer:(ZNPeer *)peer disconnectedWithError:(NSError *)error;
- (void)peer:(ZNPeer *)peer relayedTransaction:(ZNTransaction *)transaction;

@end

typedef enum {
    disconnected = 0,
    connecting,
    connected
} peerStatus;

@interface ZNPeer : NSObject<NSStreamDelegate>

@property (nonatomic, assign) id<ZNPeerDelegate> delegate;
@property (nonatomic, readonly) peerStatus status;
@property (nonatomic, readonly) NSString *host;
@property (nonatomic, readonly) uint32_t address;
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) uint64_t services;
@property (nonatomic, readonly) uint32_t version;
@property (nonatomic, readonly) uint64_t timestamp;
@property (nonatomic, readonly) NSString *useragent;
@property (nonatomic, readonly) uint32_t lastblock;

+ (instancetype)peerWithAddress:(uint32_t)address andPort:(uint16_t)port;

- (instancetype)initWithAddress:(uint32_t)address andPort:(uint16_t)port;
- (void)connect;
- (void)sendMessage:(NSData *)message type:(NSString *)type;
- (void)sendGetaddrMessage;

@end

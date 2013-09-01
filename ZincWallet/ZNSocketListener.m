//
//  ZNSocketListener.m
//  ZincWallet
//
//  Created by Aaron Voisine on 8/2/13.
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

#import "ZNSocketListener.h"
#import "ZNWallet.h"
#import "ZNKeySequence.h"
#import "ZNAddressEntity.h"
#import "ZNTransactionEntity.h"
#import "ZNTxInputEntity.h"
#import "ZNTxOutputEntity.h"
#import "ZNUnspentOutputEntity.h"
#import "NSString+Base58.h"
#import "NSMutableData+Bitcoin.h"
#import "NSManagedObject+Utils.h"
#import <AudioToolbox/AudioToolbox.h>
#import <netinet/in.h>
#import "Reachability.h"

#define SOCKET_URL @"ws://ws.blockchain.info:8335/inv"

#define LATEST_BLOCK_HEIGHT_KEY    @"LATEST_BLOCK_HEIGHT"
#define LATEST_BLOCK_TIMESTAMP_KEY @"LATEST_BLOCK_TIMESTAMP"

@interface ZNSocketListener ()

@property (nonatomic, strong) SRWebSocket *webSocket;
@property (nonatomic, assign) int connectFailCount;
@property (nonatomic, strong) id reachabilityObserver, activeObserver;

@end

@implementation ZNSocketListener

+ (instancetype)sharedInstance
{
    static id singleton = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        singleton = [self new];
    });
    return singleton;
}

- (void)openSocket
{
    if (! self.webSocket) {
        self.webSocket = [[SRWebSocket alloc] initWithURL:[NSURL URLWithString:SOCKET_URL]];
        self.webSocket.delegate = self;
        
        self.reachabilityObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:kReachabilityChangedNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) {
                if ([(Reachability *)note.object currentReachabilityStatus] != NotReachable && self.webSocket &&
                    self.webSocket.readyState != SR_OPEN && self.webSocket.readyState != SR_CONNECTING) {
                    self.webSocket = [[SRWebSocket alloc] initWithURL:[NSURL URLWithString:SOCKET_URL]];
                    self.webSocket.delegate = self;
                    [self.webSocket open];
                }
            }];
        
        self.activeObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) {
                if (self.webSocket && self.webSocket.readyState != SR_OPEN &&
                    self.webSocket.readyState != SR_CONNECTING) {
                    self.webSocket = [[SRWebSocket alloc] initWithURL:[NSURL URLWithString:SOCKET_URL]];
                    self.webSocket.delegate = self;
                    [self.webSocket open];
                }
            }];
        
        [self.webSocket open];
    }
    else if (self.webSocket.readyState != SR_OPEN && self.webSocket.readyState != SR_CONNECTING) {
        self.webSocket = [[SRWebSocket alloc] initWithURL:[NSURL URLWithString:SOCKET_URL]];
        self.webSocket.delegate = self;
        [self.webSocket open];
    }
}

- (void)closeSocket
{
    [[NSNotificationCenter defaultCenter] removeObserver:self.reachabilityObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:self.activeObserver];

    self.connectFailCount = 0;
    [self.webSocket close];
    self.webSocket = nil;
}

- (void)subscribeToAddresses:(NSArray *)addresses
{
    if (! addresses.count || self.webSocket.readyState != SR_OPEN) return;
    
    if (addresses.count > ADDRESSES_PER_QUERY) {
        [self subscribeToAddresses:[addresses subarrayWithRange:NSMakeRange(0, ADDRESSES_PER_QUERY)]];
        [self subscribeToAddresses:[addresses subarrayWithRange:NSMakeRange(ADDRESSES_PER_QUERY,
                                                                            addresses.count - ADDRESSES_PER_QUERY)]];
        return;
    }
    
    NSMutableString *msg = [NSMutableString string];
    
    for (ZNAddressEntity *a in addresses) {
        [msg appendFormat:@"{\"op\":\"addr_sub\", \"addr\":\"%@\"}", a.address];
    }
    
    NSLog(@"Websocket: %@", msg);
    
    [self.webSocket send:msg];
}

#pragma mark - SRWebSocketDelegate

- (void)webSocketDidOpen:(SRWebSocket *)webSocket
{
    NSLog(@"Websocket did open");
    
    self.connectFailCount = 0;
    
    NSLog(@"{\"op\":\"blocks_sub\"}");
    [webSocket send:@"{\"op\":\"blocks_sub\"}"];
    
    NSMutableArray *a = [NSMutableArray array];
    
    [a addObjectsFromArray:[[ZNWallet sharedInstance] addressesWithGapLimit:GAP_LIMIT_EXTERNAL internal:NO]];
    [a addObjectsFromArray:[[ZNWallet sharedInstance] addressesWithGapLimit:GAP_LIMIT_INTERNAL internal:YES]];
    [a addObjectsFromArray:[ZNAddressEntity objectsMatching:@"! (address IN %@)", [a valueForKey:@"address"]]];
    
    [self subscribeToAddresses:a];
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason
wasClean:(BOOL)wasClean
{
    NSLog(@"Websocket did close");
    
    if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive && self.connectFailCount < 5) {
        self.connectFailCount++;
        self.webSocket = [[SRWebSocket alloc] initWithURL:[NSURL URLWithString:SOCKET_URL]];
        self.webSocket.delegate = self;
        [self.webSocket open];
    }
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error;
{
    NSLog(@"Websocket did fail");
    
    if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive && self.connectFailCount < 5) {
        self.connectFailCount++;
        self.webSocket = [[SRWebSocket alloc] initWithURL:[NSURL URLWithString:SOCKET_URL]];
        self.webSocket.delegate = self;
        [self.webSocket open];
    }
}

// message will either be an NSString if the server is using text or NSData if the server is using binary.
- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)msg;
{
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSError *error = nil;
    NSData *data = [msg isKindOfClass:[NSString class]] ? [msg dataUsingEncoding:NSUTF8StringEncoding] : msg;
    NSDictionary *JSON = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        
    if (error || ! [JSON isKindOfClass:[NSDictionary class]]) {
        NSLog(@"webSocket receive error: %@", error ? error : msg);
        return;
    }
    
    NSLog(@"%@", JSON);
    
    NSString *op = JSON[@"op"];
    
    if ([op isEqual:@"utx"]) {
        ZNTransactionEntity *tx = [ZNTransactionEntity updateOrCreateWithJSON:JSON[@"x"]];

        // delete any unspent outputs that are now spent
        [tx.inputs enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [[ZNUnspentOutputEntity objectsMatching:@"txIndex == %lld && n == %d", [obj txIndex], [obj n]].lastObject
             deleteObject];
        }];
        
        // add outputs sent to wallet addresses to unspent outputs
        [tx.outputs enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            if ([[ZNWallet sharedInstance] containsAddress:(id)[obj address]] &&
                [ZNUnspentOutputEntity countObjectsMatching:@"txHash == %@ && n == %d", tx.txHash, idx] == 0) {
                [ZNUnspentOutputEntity entityWithTxOutput:obj];
            }
        }];
        
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
        //XXX [self playBeepSound];
            
        [[NSNotificationCenter defaultCenter] postNotificationName:walletBalanceNotification object:nil];
        
        [NSManagedObject saveContext];
        [defs synchronize];
    }
    else if ([op isEqual:@"block"]) {
        if (! [JSON[@"x"] isKindOfClass:[NSDictionary class]] ||
            ! [JSON[@"x"][@"height"] isKindOfClass:[NSNumber class]] ||
            ! [JSON[@"x"][@"time"] isKindOfClass:[NSNumber class]] ||
            ! [JSON[@"x"][@"txIndexes"] isKindOfClass:[NSArray class]]) {
            NSLog(@"webSocket receive error: %@", msg);
            return;
        }
        
        int height = [JSON[@"x"][@"height"] intValue];
        NSTimeInterval time = [JSON[@"x"][@"time"] doubleValue];
        NSArray *txIndexes = JSON[@"x"][@"txIndexes"];
        
        if (height) {
            [defs setInteger:height forKey:LATEST_BLOCK_HEIGHT_KEY];
            [defs setDouble:time forKey:LATEST_BLOCK_TIMESTAMP_KEY];
        }
        
        // set the block height for transactions included in the new block
        [[ZNTransactionEntity objectsMatching:@"txIndex IN %@", txIndexes]
        enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [obj setBlockHeight:height];
        }];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:walletBalanceNotification object:nil];
        
        [NSManagedObject saveContext];
        [defs synchronize];
    }
    else if ([op isEqual:@"status"]) {
        NSLog(@"%@", JSON[@"msg"]);
    }
}


@end

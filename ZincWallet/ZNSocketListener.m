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
        
        // TODO: switch to AFNetworkingReachability
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
    
    __block NSMutableString *msg = [NSMutableString string];
    
    [[addresses.lastObject managedObjectContext] performBlockAndWait:^{
        for (ZNAddressEntity *a in addresses) {
            [msg appendFormat:@"{\"op\":\"addr_sub\", \"addr\":\"%@\"}", a.address];
        }
    }];
    
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

// example utx JSON message
//{
//    op = utx;
//    x = {
//        hash = c11ab8aa71f558bd61266d72e270b30a6f687eadbbd3fdd3605657cfcd515fc7;
//        inputs = (
//            {
//                "prev_out" = {
//                    addr = 1NmG6o7MAbXhUWbtnKCF4dzh6k1erprkku;
//                    type = 0;
//                    value = 9974540;
//                };
//            }
//        );
//        "lock_time" = Unavailable;
//        out = (
//            {
//                addr = 1EyuTKk7ayNdcepz7Es3T9fH8xYBuuq54g;
//                type = 0;
//                value = 1000000;
//            },
//            {
//                addr = 17on1bqLCVWwd83kGkDBsyLRkJS8rK1Gjs;
//                type = 0;
//                value = 8974540;
//            }
//        );
//        "relayed_by" = "127.0.0.1";
//        size = 225;
//        time = 1380848035;
//        "tx_index" = 92141019;
//        "vin_sz" = 1;
//        "vout_sz" = 2;
//    };
//}

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
        __block ZNTransactionEntity *tx = [ZNTransactionEntity updateOrCreateWithJSON:JSON[@"x"]];
        NSArray *inaddrs = [ZNAddressEntity objectsMatching:@"address IN %@", [tx.inputs valueForKey:@"address"]],
                *outaddrs = [ZNAddressEntity objectsMatching:@"address IN %@", [tx.outputs valueForKey:@"address"]];
        NSMutableArray *outputs = [[ZNUnspentOutputEntity objectsSortedBy:@"txIndex" ascending:YES] mutableCopy];
        NSMutableArray *spent = [NSMutableArray array];

        if (inaddrs.count == 0 && outaddrs.count == 0) { // transaction not in wallet
            [tx deleteObject];
            return;
        }
        
        [inaddrs setValue:@(YES) forKey:@"newTx"]; // mark addresses to be updated on next wallet sync
        [outaddrs setValue:@(YES) forKey:@"newTx"];

        // delete any unspent outputs that are now spent
        [tx.inputs enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            ZNTxInputEntity *e = obj;
            
            if (e.txIndex > 0) {
                [spent addObjectsFromArray:[ZNUnspentOutputEntity objectsMatching:@"txIndex == %lld && n == %d",
                                            e.txIndex, e.n]];
            }
            else if ([[inaddrs valueForKey:@"address"] containsObject:e.address]) {
                // The utx JSON message doesn't contain either txHash or txIndex for inputs (and even combines multiple
                // inputs for the same address, WTF?!?), so try to match inputs based on just the address and amount. If
                // there is any ambiguity, ignore the whole tx. It will show up when the wallet is next synced.
                __block int32_t balance = e.value;

                [outputs enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    ZNUnspentOutputEntity *o = obj;
                     
                    if (! [o.address isEqual:e.address]) return;
                    
                    balance -= o.value;
                    [spent addObject:o];

                    if (balance <= 0) *stop = YES;
                }];

                if (balance != 0) { // tx inputs didn't match up with unspent outputs, ignore the tx
                    [tx deleteObject];
                    tx = nil;
                    *stop = YES;
                }
                else [outputs removeObjectsInArray:spent];
            }
        }];
        
        if (! tx) return;
        
        [spent makeObjectsPerformSelector:@selector(deleteObject)]; // delete spent outputs
        
        // add outputs sent to wallet addresses to unspent outputs
        [tx.outputs enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            if ([[ZNWallet sharedInstance] containsAddress:(id)[obj address]] &&
                [ZNUnspentOutputEntity countObjectsMatching:@"txHash == %@ && n == %d", tx.txHash, idx] == 0) {
                [ZNUnspentOutputEntity entityWithTxOutput:obj]; // create new unspent output object in core data
            }
        }];
        
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
        //TODO: play a beep sound
            
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

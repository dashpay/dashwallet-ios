//
//  ZNWallet+WebSocket.m
//  ZincWallet
//
//  Created by Aaron Voisine on 8/2/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNWallet+WebSocket.h"
#import "ZNElectrumSequence.h"
#import "NSString+Base58.h"
#import "NSMutableData+Bitcoin.h"
#import "WebSocketUIView.h"
#import "WebSocketNSStream.h"
#import <AudioToolbox/AudioToolbox.h>
#import <netinet/in.h>
#import "Reachability.h"


#define SOCKET_URL @"ws://ws.blockchain.info:8335/inv"

#define FUNDED_ADDRESSES_KEY       @"FUNDED_ADDRESSES"
#define SPENT_ADDRESSES_KEY        @"SPENT_ADDRESSES"
#define RECEIVE_ADDRESSES_KEY      @"RECEIVE_ADDRESSES"
#define ADDRESS_BALANCES_KEY       @"ADDRESS_BALANCES"
#define UNSPENT_OUTPUTS_KEY        @"UNSPENT_OUTPUTS"
#define TRANSACTIONS_KEY           @"TRANSACTIONS"
#define UNCONFIRMED_KEY            @"UNCONFIRMED"
#define LATEST_BLOCK_HEIGHT_KEY    @"LATEST_BLOCK_HEIGHT"
#define LATEST_BLOCK_TIMESTAMP_KEY @"LATEST_BLOCK_TIMESTAMP"

@interface ZNWallet ()

@property (nonatomic, strong) NSMutableArray *spentAddresses, *fundedAddresses, *receiveAddresses;
@property (nonatomic, strong) NSMutableDictionary *transactions, *unconfirmed;
@property (nonatomic, strong) NSMutableDictionary *unspentOutputs, *addressBalances;

@property (nonatomic, strong) WebSocket *webSocket;
@property (nonatomic, assign) int connectFailCount;
@property (nonatomic, strong) id reachabilityObserver, activeObserver;

- (NSArray *)addressesWithGapLimit:(NSUInteger)gapLimit internal:(BOOL)internal;

@end

//XXXX switch to socketrocket from zootreves's webview hack

@implementation ZNWallet (WebSocket)

- (void)openSocket
{
    if (! self.webSocket) {
        self.webSocket = [WebSocketUIView new];
        self.webSocket.delegate = self;
        
        self.reachabilityObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:kReachabilityChangedNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) {
                if ([(Reachability *)note.object currentReachabilityStatus] != NotReachable &&
                    self.webSocket.readyState != ReadyStateOpen && self.webSocket.readyState != ReadyStateConnecting) {
                    [self.webSocket connect:SOCKET_URL];
                }
            }];
        
        self.activeObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) {
                if (self.webSocket.readyState != ReadyStateOpen && self.webSocket.readyState != ReadyStateConnecting) {
                    [self.webSocket connect:SOCKET_URL];
                }
            }];
        
        [self.webSocket connect:SOCKET_URL];
    }
    else if (self.webSocket.readyState != ReadyStateOpen && self.webSocket.readyState != ReadyStateConnecting) {
        [self.webSocket connect:SOCKET_URL];
    }
}

- (void)closeSocket
{
    [[NSNotificationCenter defaultCenter] removeObserver:self.reachabilityObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:self.activeObserver];

    [self.webSocket disconnect];
    self.webSocket = nil;
}

#pragma mark - WebSocketDelegate

- (void)subscribeToAddresses:(NSArray *)addresses
{
    if (! addresses.count || self.webSocket.readyState != ReadyStateOpen) return;
    
    if (addresses.count > ADDRESSES_PER_QUERY) {
        [self subscribeToAddresses:[addresses subarrayWithRange:NSMakeRange(0, ADDRESSES_PER_QUERY)]];
        [self subscribeToAddresses:[addresses subarrayWithRange:NSMakeRange(ADDRESSES_PER_QUERY,
                                                                            addresses.count - ADDRESSES_PER_QUERY)]];
        return;
    }
    
    NSMutableString *msg = [NSMutableString string];
    
    for (NSString *addr in addresses) {
        [msg appendFormat:@"{\"op\":\"addr_sub\", \"addr\":\"%@\"}", addr];
    }
    
    NSLog(@"%@", msg);
    
    [self.webSocket send:msg];
}

- (void)webSocketOnOpen:(WebSocket*)webSocket
{
    NSLog(@"Websocket on open");
    
    self.connectFailCount = 0;
    
    NSLog(@"{\"op\":\"blocks_sub\"}");
    [webSocket send:@"{\"op\":\"blocks_sub\"}"];
    
    [self subscribeToAddresses:[self addressesWithGapLimit:ELECTURM_GAP_LIMIT internal:NO]];
    [self subscribeToAddresses:[self addressesWithGapLimit:ELECTURM_GAP_LIMIT_FOR_CHANGE internal:YES]];
    [self subscribeToAddresses:self.fundedAddresses];
    [self subscribeToAddresses:self.spentAddresses];
}

- (void)webSocketOnClose:(WebSocket*)webSocket
{
    NSLog(@"Websocket on close");
    
    if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive && self.connectFailCount < 5) {
        self.connectFailCount++;
        [webSocket connect:SOCKET_URL];
    }
}

- (void)webSocket:(WebSocket*)webSocket onError:(NSError*)error
{
    NSLog(@"Websocket on error");
    
    if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive && self.connectFailCount < 5) {
        self.connectFailCount++;
        [webSocket connect:SOCKET_URL];
    }
}

- (void)webSocket:(WebSocket*)webSocket onReceive:(NSData*)data
{ //Data is only until this function returns (You cannot retain it!)
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        NSError *error = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        
        if (error || ! json) {
            NSLog(@"webSocket receive error: %@", error ? error.localizedDescription : [data description]);
            return;
        }
        
        NSLog(@"%@", json);
        
        NSString *op = json[@"op"];
        
        if ([op isEqual:@"utx"]) {
            NSDictionary *x = json[@"x"];
            NSMutableSet *updated = [NSMutableSet set];
            
            @synchronized(self) {
                if (x[@"hash"]) {
                    [self.unconfirmed removeObjectForKey:x[@"hash"]];
                    self.transactions[x[@"hash"]] = [NSDictionary dictionaryWithDictionary:x];
                }
                
                [x[@"out"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    NSString *addr = obj[@"addr"];
                    uint64_t value = [obj[@"value"] unsignedLongLongValue];
                    
                    [updated addObject:addr];
                    
                    if (value == 0 || ! addr || ! [self containsAddress:addr]) return;
                    
                    uint64_t balance = [self.addressBalances[addr] unsignedLongLongValue] + value;
                    
                    self.addressBalances[addr] = @(balance);
                    if (! [self.fundedAddresses containsObject:addr]) [self.fundedAddresses addObject:addr];
                    [self.spentAddresses removeObject:addr];
                    [self.receiveAddresses removeObject:addr];
                    
                    NSMutableData *script = [NSMutableData data];
                    
                    [script appendScriptPubKeyForAddress:addr];
                    
                    self.unspentOutputs[[x[@"hash"] stringByAppendingFormat:@"%d", idx]] =
                    @{@"tx_hash":x[@"hash"], @"tx_index":x[@"tx_index"], @"tx_output_n":@(idx),
                      @"script":[NSString hexWithData:script], @"value":@(value), @"confirmations":@(0)};
                }];
                
                // don't update addressTxCount so the address's unspent outputs will be updated on next sync
                //[updated enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
                //    self.addressTxCount[obj] = @([self.addressTxCount[obj] unsignedIntegerValue] + 1);
                //}];
                
                [defs setObject:self.unconfirmed forKey:UNCONFIRMED_KEY];
                [defs setObject:self.transactions forKey:TRANSACTIONS_KEY];
                [defs setObject:self.addressBalances forKey:ADDRESS_BALANCES_KEY];
                [defs setObject:self.fundedAddresses forKey:FUNDED_ADDRESSES_KEY];
                [defs setObject:self.spentAddresses forKey:SPENT_ADDRESSES_KEY];
                [defs setObject:self.receiveAddress forKey:RECEIVE_ADDRESSES_KEY];
                [defs setObject:self.unspentOutputs forKey:UNSPENT_OUTPUTS_KEY];
            }
            
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
            //XXX [self playBeepSound];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:walletBalanceNotification object:self];
            });
            
            [defs synchronize];
        }
        else if ([op isEqual:@"block"]) {
            NSDictionary *x = json[@"x"];
            NSUInteger height = [x[@"height"] unsignedIntegerValue];
            NSTimeInterval time = [x[@"time"] doubleValue];
            NSArray *txIndexes = x[@"txIndexes"];
            __block BOOL confirmed = NO;
            
            @synchronized(self) {
                if (height) {
                    [defs setInteger:height forKey:LATEST_BLOCK_HEIGHT_KEY];
                    [defs setDouble:time forKey:LATEST_BLOCK_TIMESTAMP_KEY];
                }
                
                [[self.transactions keysOfEntriesPassingTest:^BOOL(id key, id obj, BOOL *stop) {
                    return [txIndexes containsObject:obj[@"tx_index"]];
                }] enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
                    NSMutableDictionary *tx = [NSMutableDictionary dictionaryWithDictionary:self.transactions[obj]];
                    
                    tx[@"block_height"] = @(height);
                    self.transactions[obj] = tx;
                    confirmed = YES;
                }];
                
                if (confirmed) [defs setObject:self.transactions forKey:TRANSACTIONS_KEY];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:walletBalanceNotification object:self];
            });
            
            [defs synchronize];
        }
        else if ([op isEqual:@"status"]) {
            NSLog(@"%@", json[@"msg"]);
        }
    });
}


@end

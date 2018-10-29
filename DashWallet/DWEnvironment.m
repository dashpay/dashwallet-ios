//
//  DWEnvironment.m
//  DashWallet
//
//  Created by Sam Westrich on 10/25/18.
//  Copyright © 2018 Dash Core. All rights reserved.
//

#import "DWEnvironment.h"

@implementation DWEnvironment

+ (instancetype)sharedInstance
{
    static id singleton = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        singleton = [self new];
    });
    
    return singleton;
}

- (instancetype)init
{
    if (! (self = [super init])) return nil;
#if DASH_TESTNET
    self.currentChain = [DSChain testnet];
#else
    self.currentChain = [DSChain mainnet];
#endif
    [self reset];
    
    return self;
}

-(void)reset {
    self.currentChainPeerManager = [[DSChainManager sharedInstance] peerManagerForChain:self.currentChain];
}

-(DSWallet*)currentWallet {
    return [[self.currentChain wallets] firstObject];
}

-(DSWallet*)currentAccount {
    return [[self.currentWallet accounts] firstObject];
}


- (void)clearWallet {
    [self.currentChain unregisterWallet:[DWEnvironment sharedInstance].currentWallet];
}

@end

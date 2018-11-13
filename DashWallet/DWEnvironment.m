//
//  DWEnvironment.m
//  DashWallet
//
//  Created by Sam Westrich on 10/25/18.
//  Copyright © 2018 Dash Core. All rights reserved.
//

#import "DWEnvironment.h"

#define CURRENT_CHAIN_TYPE_KEY @"CURRENT_CHAIN_TYPE_KEY"

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
    NSUserDefaults * userDefaults = [NSUserDefaults standardUserDefaults];
    if (![userDefaults objectForKey:CURRENT_CHAIN_TYPE_KEY]) {
        [userDefaults setInteger:DSChainType_MainNet forKey:CURRENT_CHAIN_TYPE_KEY];
    }
    [self reset];
    
    return self;
}

-(void)reset {
    NSUserDefaults * userDefaults = [NSUserDefaults standardUserDefaults];
    DSChainType chainType = [userDefaults integerForKey:CURRENT_CHAIN_TYPE_KEY];
    switch (chainType) {
        case DSChainType_MainNet:
            self.currentChain = [DSChain mainnet];
            break;
        case DSChainType_TestNet:
            self.currentChain = [DSChain testnet];
            break;
        default:
            break;
    }
    self.currentChainPeerManager = [[DSChainManager sharedInstance] peerManagerForChain:self.currentChain];
}

-(DSWallet*)currentWallet {
    return [[self.currentChain wallets] firstObject];
}

-(DSWallet*)currentAccount {
    return [[self.currentWallet accounts] firstObject];
}


- (void)clearWallet {
    [[DashSync sharedSyncController] stopSyncForChain:self.currentChain];
    [[DashSync sharedSyncController] wipeBlockchainDataForChain:self.currentChain];
    [[DashSync sharedSyncController] wipeSporkDataForChain:self.currentChain];
    [[DashSync sharedSyncController] wipeMasternodeDataForChain:self.currentChain];
    [self.currentChain unregisterWallet:[DWEnvironment sharedInstance].currentWallet];
}

- (void)switchToMainnet {
    if (self.currentChain != [DSChain mainnet]) {
        [DSEventManager saveEvent:@"settings:change_network_mainnet"];
        [self switchToNetwork:DSChainType_MainNet];
    }
}

- (void)switchToTestnet {
    if (self.currentChain != [DSChain testnet]) {
        [DSEventManager saveEvent:@"settings:change_network_testnet"];
        [self switchToNetwork:DSChainType_TestNet];
    }
}

- (void)switchToNetwork:(DSChainType)chainType {
    DSWallet * wallet = [self currentWallet];
    [[DashSync sharedSyncController] stopSyncForChain:self.currentChain];
    NSUserDefaults * userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setInteger:chainType forKey:CURRENT_CHAIN_TYPE_KEY];
    [self reset];
    if (![self.currentChain hasAWallet]) {
        [wallet copyForChain:self.currentChain completion:^(DSWallet * _Nullable copiedWallet) {
            
        }];
    }
    [self.currentChainPeerManager connect];
}

@end

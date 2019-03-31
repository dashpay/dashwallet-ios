//
//  DWEnvironment.m
//  DashWallet
//
//  Created by Sam Westrich on 10/25/18.
//  Copyright © 2019 Dash Core. All rights reserved.
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
    [[DSChainsManager sharedInstance] chainManagerForChain:[DSChain mainnet]]; //initialization
    [[DSChainsManager sharedInstance] chainManagerForChain:[DSChain testnet]]; //initialization
    [self reset];
    
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)[[NSBundle mainBundle] URLForResource:@"coinflip"
                                                                                withExtension:@"aiff"], &_pingsound);
    
    return self;
}

- (void)dealloc
{
    AudioServicesDisposeSystemSoundID(self.pingsound);
}

-(void)playPingSound {
    AudioServicesPlaySystemSound(self.pingsound);
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
    self.currentChainManager = [[DSChainsManager sharedInstance] chainManagerForChain:self.currentChain];
}

-(DSWallet*)currentWallet {
    return [[self.currentChain wallets] firstObject];
}

-(DSWallet*)currentAccount {
    return [[self.currentWallet accounts] firstObject];
}

-(NSArray*)allWallets {
    return [[DSChainsManager sharedInstance] allWallets];
}

- (void)clearAllWallets {
    [[DashSync sharedSyncController] stopSyncForChain:self.currentChain];
    for (DSChain * chain in [[DSChainsManager sharedInstance] chains]) {
        [[DashSync sharedSyncController] wipeBlockchainDataForChain:chain];
        [[DashSync sharedSyncController] wipeSporkDataForChain:chain];
        [[DashSync sharedSyncController] wipeMasternodeDataForChain:chain];
        [chain unregisterAllWallets];
    }
    [[DSAuthenticationManager sharedInstance] removePin]; //this can only work if there are no wallets
}

- (void)switchToMainnetWithCompletion:(void (^)(BOOL success))completion {
    if (self.currentChain != [DSChain mainnet]) {
        [DSEventManager saveEvent:@"settings:change_network_mainnet"];
        [self switchToNetwork:DSChainType_MainNet withCompletion:completion];
    }
}

- (void)switchToTestnetWithCompletion:(void (^)(BOOL success))completion  {
    if (self.currentChain != [DSChain testnet]) {
        [DSEventManager saveEvent:@"settings:change_network_testnet"];
        [self switchToNetwork:DSChainType_TestNet withCompletion:completion];
    }
}

- (void)switchToNetwork:(DSChainType)chainType withCompletion:(void (^)(BOOL success))completion {
    NSUserDefaults * userDefaults = [NSUserDefaults standardUserDefaults];
    DSChainType originalChainType = [userDefaults integerForKey:CURRENT_CHAIN_TYPE_KEY];
    if (originalChainType == chainType) {
        completion(YES); //didn't really switch but good enough
        return;
    }
    DSWallet * wallet = [self currentWallet];
    DSChain * destinationChain = nil;
    switch (chainType) {
        case DSChainType_MainNet:
            destinationChain = [DSChain mainnet];
            break;
        case DSChainType_TestNet:
            destinationChain = [DSChain testnet];
            break;
        default:
            break;
    }
    if (![destinationChain hasAWallet]) {
        [wallet copyForChain:destinationChain completion:^(DSWallet * _Nullable copiedWallet) {
            if (copiedWallet) {
                [[DashSync sharedSyncController] stopSyncForChain:self.currentChain];
                [userDefaults setInteger:chainType forKey:CURRENT_CHAIN_TYPE_KEY];
                [self reset];
                [self.currentChainManager.peerManager connect];
                completion(YES);
            } else {
                completion(NO);
            }
        }];
    } else {
        [[DashSync sharedSyncController] stopSyncForChain:self.currentChain];
        [userDefaults setInteger:chainType forKey:CURRENT_CHAIN_TYPE_KEY];
        [self reset];
        [self.currentChainManager.peerManager connect];
        completion(YES);
    }
    
}

@end

//
//  Created by Sam Westrich
//  Copyright © 2018-2019 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "DWEnvironment.h"

#define CURRENT_CHAIN_TYPE_KEY @"CURRENT_CHAIN_TYPE_KEY"

NSNotificationName const DWCurrentNetworkDidChangeNotification = @"DWCurrentNetworkDidChangeNotification";
static NSString *const DWDevnetEvonetIdentifier = @"devnet-mobile";

@implementation DWEnvironment

+ (instancetype)sharedInstance {
    static id singleton = nil;
    static dispatch_once_t onceToken = 0;

    dispatch_once(&onceToken, ^{
        singleton = [self new];
    });

    return singleton;
}

- (instancetype)init {
    if (!(self = [super init]))
        return nil;

    [NSString setDashCurrencySymbolAssetName:@"icon_dash_currency"];

    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    if (![userDefaults objectForKey:CURRENT_CHAIN_TYPE_KEY]) {
        [userDefaults setInteger:DSChainType_MainNet forKey:CURRENT_CHAIN_TYPE_KEY];
    }
    [[DSChainsManager sharedInstance] chainManagerForChain:[DSChain mainnet]]; //initialization
    [[DSChainsManager sharedInstance] chainManagerForChain:[DSChain testnet]]; //initialization
    DSChain *evonet = [DSChain devnetWithIdentifier:DWDevnetEvonetIdentifier];
    if (evonet) {
        [evonet setDevnetNetworkName:@"Evonet"];
        [[DSChainsManager sharedInstance] chainManagerForChain:evonet];
    }
    [self reset];

    return self;
}

- (void)reset {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    DSChainType chainType = [userDefaults integerForKey:CURRENT_CHAIN_TYPE_KEY];
    switch (chainType) {
        case DSChainType_MainNet:
            self.currentChain = [DSChain mainnet];
            break;
        case DSChainType_TestNet:
            self.currentChain = [DSChain testnet];
            break;
        case DSChainType_DevNet: //we will only have evonet
            self.currentChain = [DSChain devnetWithIdentifier:DWDevnetEvonetIdentifier];
            break;
        default:
            break;
    }
    self.currentChainManager = [[DSChainsManager sharedInstance] chainManagerForChain:self.currentChain];
}

- (DSWallet *)currentWallet {
    return [[self.currentChain wallets] firstObject];
}

- (DSAccount *)currentAccount {
    return [[self.currentWallet accounts] firstObject];
}

- (NSArray *)allWallets {
    return [[DSChainsManager sharedInstance] allWallets];
}

- (void)clearAllWallets {
    [self clearAllWalletsAndRemovePin:YES];
}

- (void)clearAllWalletsAndRemovePin:(BOOL)shouldRemovePin {
    [[DashSync sharedSyncController] stopSyncForChain:self.currentChain];
    NSManagedObjectContext *context = [NSManagedObjectContext chainContext];
    for (DSChain *chain in [[DSChainsManager sharedInstance] chains]) {
        [[DashSync sharedSyncController] wipeBlockchainNonTerminalDataForChain:chain inContext:context];
        [chain unregisterAllWallets];
    }

    if (shouldRemovePin) {
        [[DSAuthenticationManager sharedInstance] removePin]; //this can only work if there are no wallets
    }
}

- (void)switchToMainnetWithCompletion:(void (^)(BOOL success))completion {
    if (self.currentChain != [DSChain mainnet]) {
        [self switchToNetwork:DSChainType_MainNet withIdentifier:nil withCompletion:completion];
    }
}

- (void)switchToTestnetWithCompletion:(void (^)(BOOL success))completion {
    if (self.currentChain != [DSChain testnet]) {
        [self switchToNetwork:DSChainType_TestNet withIdentifier:nil withCompletion:completion];
    }
}

- (void)switchToEvonetWithCompletion:(void (^)(BOOL success))completion {
    if (self.currentChain != [DSChain devnetWithIdentifier:DWDevnetEvonetIdentifier]) {
        [self switchToNetwork:DSChainType_DevNet withIdentifier:DWDevnetEvonetIdentifier withCompletion:completion];
    }
}

- (NSOrderedSet *)evonetServiceLocation {
    NSMutableArray *serviceLocations = [NSMutableArray array];
    [serviceLocations addObject:@"34.222.170.127"];
    [serviceLocations addObject:@"34.217.61.209"];
    [serviceLocations addObject:@"54.214.177.132"];
    //shuffle them
    NSUInteger count = [serviceLocations count];
    for (NSUInteger i = 0; i < count - 1; ++i) {
        NSInteger remainingCount = count - i;
        NSInteger exchangeIndex = i + arc4random_uniform((u_int32_t)remainingCount);
        [serviceLocations exchangeObjectAtIndex:i withObjectAtIndex:exchangeIndex];
    }
    return [NSOrderedSet orderedSetWithArray:serviceLocations];
}

- (void)switchToNetwork:(DSChainType)chainType withIdentifier:(NSString *)identifier withCompletion:(void (^)(BOOL success))completion {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    DSChainType originalChainType = [userDefaults integerForKey:CURRENT_CHAIN_TYPE_KEY];
    if (originalChainType == chainType) {
        // Notification isn't send here as the chain remains the same
        completion(YES); //didn't really switch but good enough
        return;
    }
    DSWallet *wallet = [self currentWallet];
    DSChain *destinationChain = nil;
    switch (chainType) {
        case DSChainType_MainNet:
            destinationChain = [DSChain mainnet];
            break;
        case DSChainType_TestNet:
            destinationChain = [DSChain testnet];
            break;
        case DSChainType_DevNet:
            destinationChain = [DSChain devnetWithIdentifier:identifier];
            if (!destinationChain && [identifier isEqualToString:DWDevnetEvonetIdentifier]) {
                // TODO: provide valid `dpnsContractID` and `dashpayContractID`
                destinationChain = [[DSChainsManager sharedInstance]
                    registerDevnetChainWithIdentifier:identifier
                                  forServiceLocations:[self evonetServiceLocation]
                                         standardPort:20001
                                         dapiJRPCPort:3000
                                         dapiGRPCPort:3010
                                       dpnsContractID:@"ForwNrvKy8jdyoCNTYBK4gcV6o15n79DmFQio2gGac5p".base58ToData.UInt256
                                    dashpayContractID:@"2VkEDxMJESJ379oY14rm3DBLrmu58BW8KCtPcfWe1Wss".base58ToData.UInt256
                                      protocolVersion:70215
                                   minProtocolVersion:70215
                                         sporkAddress:@"yQuAu9YAMt4yEiXBeDp3q5bKpo7jsC2eEj"
                                      sporkPrivateKey:@"cVk6u16fT1Pwd9MugowSt7VmNzN8ozE4wJjfJGC97Hf43oxRMjar"];
                [destinationChain setDevnetNetworkName:@"Evonet"];
            }
            break;
        default:
            break;
    }
    if (!destinationChain)
        return;
    if (![destinationChain hasAWallet]) {
        [wallet copyForChain:destinationChain
                  completion:^(DSWallet *_Nullable copiedWallet) {
                      if (copiedWallet) {
                          NSAssert([NSThread isMainThread], @"Main thread is assumed here");
                          [[DashSync sharedSyncController] stopSyncForChain:self.currentChain];
                          [userDefaults setInteger:chainType forKey:CURRENT_CHAIN_TYPE_KEY];
                          [self reset];
                          [self.currentChainManager.peerManager connect];
                          [[NSNotificationCenter defaultCenter] postNotificationName:DWCurrentNetworkDidChangeNotification
                                                                              object:nil];
                          completion(YES);
                      }
                      else {
                          completion(NO);
                      }
                  }];
    }
    else {
        NSAssert([NSThread isMainThread], @"Main thread is assumed here");
        [[DashSync sharedSyncController] stopSyncForChain:self.currentChain];
        [userDefaults setInteger:chainType forKey:CURRENT_CHAIN_TYPE_KEY];
        [self reset];
        [self.currentChainManager.peerManager connect];
        [[NSNotificationCenter defaultCenter] postNotificationName:DWCurrentNetworkDidChangeNotification
                                                            object:nil];
        completion(YES);
    }
}

@end

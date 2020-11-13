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
NSNotificationName const DWWillWipeWalletNotification = @"DWWillWipeWalletNotification";
static NSString *const DWMobileDevnetIdentifier = @"devnet-mobile-2";
static NSString *const DWPalinkaDevnetIdentifier = @"devnet-palinka";

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
        //        [userDefaults setInteger:DSChainType_MainNet forKey:CURRENT_CHAIN_TYPE_KEY];
        // TODO: DP specific (for use in DashPay only)
        [userDefaults setInteger:DSChainType_DevNet forKey:CURRENT_CHAIN_TYPE_KEY];
        // END TODO
    }
    [[DSChainsManager sharedInstance] chainManagerForChain:[DSChain mainnet]]; //initialization
    [[DSChainsManager sharedInstance] chainManagerForChain:[DSChain testnet]]; //initialization
    DSChain *evonet = [DSChain devnetWithIdentifier:[self currentDevnetIdentifier]];
    // TODO: DP specific (for use in DashPay only)
    if (evonet == nil) {
        evonet = [self currentDevnetChain];
    }
    // END TODO
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
            self.currentChain = [DSChain devnetWithIdentifier:[self currentDevnetIdentifier]];
            if (!self.currentChain) {
                NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
                [userDefaults setInteger:DSChainType_MainNet forKey:CURRENT_CHAIN_TYPE_KEY];
                self.currentChain = [DSChain mainnet];
            }
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
    [[NSNotificationCenter defaultCenter] postNotificationName:DWWillWipeWalletNotification object:self];

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
    NSString *devnetIdentifier = [self currentDevnetIdentifier];
    if (self.currentChain != [DSChain devnetWithIdentifier:devnetIdentifier]) {
        [self switchToNetwork:DSChainType_DevNet withIdentifier:devnetIdentifier withCompletion:completion];
    }
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
            if (!destinationChain && [identifier isEqualToString:[self currentDevnetIdentifier]]) {
                destinationChain = [self currentDevnetChain];
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
        if (self.currentChain) {
            [[DashSync sharedSyncController] stopSyncForChain:self.currentChain];
        }
        [userDefaults setInteger:chainType forKey:CURRENT_CHAIN_TYPE_KEY];
        [self reset];
        [self.currentChainManager.peerManager connect];
        [[NSNotificationCenter defaultCenter] postNotificationName:DWCurrentNetworkDidChangeNotification
                                                            object:nil];
        completion(YES);
    }
}

- (NSOrderedSet *)mobileDevnetServiceLocation {
    NSMutableArray *serviceLocations = [NSMutableArray array];
    [serviceLocations addObject:@"34.219.177.88"];
    [serviceLocations addObject:@"52.12.115.4"];
    [serviceLocations addObject:@"34.222.93.50"];
    [serviceLocations addObject:@"52.27.96.24"];
    [serviceLocations addObject:@"34.222.63.37"];
    [serviceLocations addObject:@"34.219.147.102"];
    [serviceLocations addObject:@"52.24.159.236"];
    [serviceLocations addObject:@"34.216.79.150"];
    [serviceLocations addObject:@"34.214.159.94"];
    [serviceLocations addObject:@"52.13.103.87"];
    [serviceLocations addObject:@"34.220.91.64"];
    [serviceLocations addObject:@"54.185.66.134"];
    [serviceLocations addObject:@"35.167.229.36"];
    //shuffle them
    NSUInteger count = [serviceLocations count];
    for (NSUInteger i = 0; i < count - 1; ++i) {
        NSInteger remainingCount = count - i;
        NSInteger exchangeIndex = i + arc4random_uniform((u_int32_t)remainingCount);
        [serviceLocations exchangeObjectAtIndex:i withObjectAtIndex:exchangeIndex];
    }
    return [NSOrderedSet orderedSetWithArray:serviceLocations];
}

- (NSOrderedSet *)palinkaDevnetServiceLocation {
    NSMutableArray *serviceLocations = [NSMutableArray array];
    [serviceLocations addObject:@"35.160.208.146"];
    [serviceLocations addObject:@"52.25.119.181"];
    [serviceLocations addObject:@"34.217.123.47"];
    [serviceLocations addObject:@"54.187.180.191"];
    [serviceLocations addObject:@"54.218.238.240"];
    [serviceLocations addObject:@"54.214.223.133"];
    [serviceLocations addObject:@"34.216.205.76"];
    [serviceLocations addObject:@"34.217.44.188"];
    [serviceLocations addObject:@"54.212.184.233"];
    [serviceLocations addObject:@"34.216.221.94"];
    [serviceLocations addObject:@"34.219.217.150"];
    [serviceLocations addObject:@"34.222.170.91"];
    [serviceLocations addObject:@"54.213.188.235"];
    [serviceLocations addObject:@"44.230.162.12"];
    //shuffle them
    NSUInteger count = [serviceLocations count];
    for (NSUInteger i = 0; i < count - 1; ++i) {
        NSInteger remainingCount = count - i;
        NSInteger exchangeIndex = i + arc4random_uniform((u_int32_t)remainingCount);
        [serviceLocations exchangeObjectAtIndex:i withObjectAtIndex:exchangeIndex];
    }
    return [NSOrderedSet orderedSetWithArray:serviceLocations];
}

- (NSString *)currentDevnetIdentifier {
    return DWPalinkaDevnetIdentifier;
}

- (DSChain *)currentDevnetChain {
    return [self palinkaDevnetChain];
}

- (DSChain *)mobileDevnetChain {
    return [[DSChainsManager sharedInstance]
        registerDevnetChainWithIdentifier:DWMobileDevnetIdentifier
                      forServiceLocations:[self mobileDevnetServiceLocation]
              withMinimumDifficultyBlocks:UINT32_MAX
                             standardPort:20001
                             dapiJRPCPort:3000
                             dapiGRPCPort:3010
                           dpnsContractID:@"CVZzFCbz4Rcf2Lmu9mvtC1CmvPukHy5kS2LNtNaBFM2N".base58ToData.UInt256
                        dashpayContractID:@"Du2kswW2h1gNVnTWdfNdSxBrC2F9ofoaZsXA6ki1PhG6".base58ToData.UInt256
                          protocolVersion:70216
                       minProtocolVersion:70216
                             sporkAddress:@"yMtULrhoxd8vRZrsnFobWgRTidtjg2Rnjm"
                          sporkPrivateKey:@"cRsR7ywG6bhb5JsnpeRJ4c1fACabmYtK6WUVPiGG3GG4a5iYk6iL"];
}

- (DSChain *)palinkaDevnetChain {
    return [[DSChainsManager sharedInstance]
        registerDevnetChainWithIdentifier:DWPalinkaDevnetIdentifier
                      forServiceLocations:[self palinkaDevnetServiceLocation]
              withMinimumDifficultyBlocks:UINT32_MAX
                             standardPort:20001
                             dapiJRPCPort:3000
                             dapiGRPCPort:3010
                           dpnsContractID:@"H9AxLAvgxEpq72pDg41nsqR3bY5Cv9hTT6yZdKzY3PaE".base58ToData.UInt256
                        dashpayContractID:@"Fxf3w1rsUvRxW8WsVnQcUNgtgVn8w47BwZtQPAsJWkkH".base58ToData.UInt256
                          protocolVersion:70218
                       minProtocolVersion:70218
                             sporkAddress:@"yMtULrhoxd8vRZrsnFobWgRTidtjg2Rnjm"
                          sporkPrivateKey:@"cRsR7ywG6bhb5JsnpeRJ4c1fACabmYtK6WUVPiGG3GG4a5iYk6iL"];
}

@end

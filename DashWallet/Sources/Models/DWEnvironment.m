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
static NSString *const DWEvoDevnetIdentifier = @"devnet-evonet-8";

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

- (NSOrderedSet *)evoDevnetServiceLocation {
    NSMutableArray *serviceLocations = [NSMutableArray array];
    [serviceLocations addObject:@"54.188.72.112"];
    [serviceLocations addObject:@"18.236.235.220"];
    [serviceLocations addObject:@"54.190.1.129"];
    [serviceLocations addObject:@"52.88.52.65"];
    [serviceLocations addObject:@"54.189.121.60"];
    [serviceLocations addObject:@"34.219.43.9"];
    [serviceLocations addObject:@"54.69.71.240"];
    [serviceLocations addObject:@"34.219.79.193"];
    [serviceLocations addObject:@"54.184.89.215"];
    [serviceLocations addObject:@"54.189.73.226"];
    [serviceLocations addObject:@"52.88.13.87"];
    [serviceLocations addObject:@"34.220.159.57"];
    [serviceLocations addObject:@"34.220.38.59"];
    [serviceLocations addObject:@"34.221.226.198"];
    [serviceLocations addObject:@"54.190.26.250"];
    [serviceLocations addObject:@"54.202.214.68"];
    [serviceLocations addObject:@"34.222.91.196"];
    [serviceLocations addObject:@"54.149.99.26"];
    [serviceLocations addObject:@"54.186.22.30"];
    [serviceLocations addObject:@"54.190.136.191"];
    [serviceLocations addObject:@"34.221.185.231"];
    [serviceLocations addObject:@"52.33.251.111"];
    [serviceLocations addObject:@"35.167.226.182"];
    [serviceLocations addObject:@"54.184.71.154"];
    [serviceLocations addObject:@"35.164.4.147"];
    [serviceLocations addObject:@"54.186.133.94"];
    [serviceLocations addObject:@"54.203.2.102"];
    [serviceLocations addObject:@"34.216.133.190"];
    [serviceLocations addObject:@"54.212.206.131"];
    [serviceLocations addObject:@"34.221.5.65"];
    [serviceLocations addObject:@"54.244.159.60"];
    [serviceLocations addObject:@"52.25.73.91"];
    [serviceLocations addObject:@"54.186.129.244"];
    [serviceLocations addObject:@"52.32.251.203"];
    [serviceLocations addObject:@"34.212.169.216"];
    [serviceLocations addObject:@"211.30.243.82"];
    [serviceLocations addObject:@"18.237.194.30"];
    [serviceLocations addObject:@"54.244.203.43"];
    [serviceLocations addObject:@"54.200.73.105"];
    [serviceLocations addObject:@"54.149.181.16"];
    [serviceLocations addObject:@"54.187.128.127"];
    [serviceLocations addObject:@"54.186.145.12"];
    [serviceLocations addObject:@"18.237.255.133"];
    [serviceLocations addObject:@"18.236.73.143"];
    [serviceLocations addObject:@"54.245.217.116"];
    [serviceLocations addObject:@"34.214.12.133"];
    [serviceLocations addObject:@"54.185.186.111"];
    [serviceLocations addObject:@"52.88.38.138"];
    [serviceLocations addObject:@"18.236.139.199"];
    [serviceLocations addObject:@"34.223.226.20"];
    [serviceLocations addObject:@"35.167.241.7"];
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
    return DWEvoDevnetIdentifier;
}

- (DSChain *)currentDevnetChain {
    return [self evoDevnetChain];
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

- (DSChain *)evoDevnetChain {
    return [[DSChainsManager sharedInstance]
        registerDevnetChainWithIdentifier:DWEvoDevnetIdentifier
                      forServiceLocations:[self evoDevnetServiceLocation]
              withMinimumDifficultyBlocks:UINT32_MAX
                             standardPort:20001
                             dapiJRPCPort:3000
                             dapiGRPCPort:3010
                           dpnsContractID:@"3VvS19qomuGSbEYWbTsRzeuRgawU3yK4fPMzLrbV62u8".base58ToData.UInt256
                        dashpayContractID:@"FrXpVEsxFZ9hgCpiXwWbsQe4xHB9wZHGj4Lg5UjgxtHb".base58ToData.UInt256
                          protocolVersion:70218
                       minProtocolVersion:70218
                             sporkAddress:@"yQuAu9YAMt4yEiXBeDp3q5bKpo7jsC2eEj"
                          sporkPrivateKey:@"cVk6u16fT1Pwd9MugowSt7VmNzN8ozE4wJjfJGC97Hf43oxRMjar"];
}

@end

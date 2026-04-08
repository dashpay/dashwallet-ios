//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

#import "DWRecoverWalletCommand.h"

#import <DashSync/DSAuthenticationManager+Private.h>

#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWRecoverWalletCommand ()

@property (readonly, nonatomic, copy) NSString *phrase;

@end

@implementation DWRecoverWalletCommand

- (instancetype)initWithPhrase:(NSString *)phrase {
    NSParameterAssert(phrase);

    self = [super init];
    if (self) {
        _phrase = CFBridgingRelease(CFStringCreateCopy(SecureAllocator(), (CFStringRef)phrase));
    }
    return self;
}

- (void)execute {
    [self recoverWalletWithPhrase:self.phrase];
}

#pragma mark - Private

- (void)recoverWalletWithPhrase:(NSString *)phrase {
    DSChain *chain = [[DWEnvironment sharedInstance] currentChain];
    NSParameterAssert(chain);
    [DSWallet standardWalletWithSeedPhrase:phrase
                           setCreationDate:BIP39_WALLET_UNKNOWN_CREATION_TIME
                                  forChain:chain
                           storeSeedPhrase:YES
                               isTransient:NO];

    // Also import the wallet into SwiftDashSDK so restored users get a
    // SwiftDashSDK side from day one — same end state as fresh-install
    // and upgraded users. The two libraries run independently; DashSync
    // continues to own its own state.
    [self importWalletIntoSwiftDashSDK:phrase forChain:chain];

    [DWGlobalOptions sharedInstance].resyncingWallet = YES;

    // START_SYNC_ENTRY_POINT
    [[DWEnvironment sharedInstance].currentChainManager startSync];
}

- (void)importWalletIntoSwiftDashSDK:(NSString *)phrase forChain:(DSChain *)chain {
    if (phrase.length == 0) {
        return;
    }

    NSError *pinError = nil;
    NSString *pin = [[DSAuthenticationManager sharedInstance] getPin:&pinError];
    if (pin.length == 0) {
        return;
    }

    DWSwiftDashSDKNetwork network;
    switch (chain.chainType.tag) {
        case ChainType_MainNet:
            network = DWSwiftDashSDKNetworkMainnet;
            break;
        case ChainType_TestNet:
            network = DWSwiftDashSDKNetworkTestnet;
            break;
        default:
            return; // devnet/regtest unsupported in v1
    }

    [DWSwiftDashSDKWalletCreator importWalletWithMnemonic:phrase pin:pin network:network];
}

@end

NS_ASSUME_NONNULL_END

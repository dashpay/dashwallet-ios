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

#import "DWGlobalOptions.h"
#import "DWSecureAllocator.h"
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
        _phrase = CFBridgingRelease(CFStringCreateCopy(DWSecureAllocator(), (CFStringRef)phrase));
    }
    return self;
}

- (void)execute {
    [self recoverWalletWithPhrase:self.phrase];
}

#pragma mark - Private

- (void)recoverWalletWithPhrase:(NSString *)phrase {
    [self importWalletIntoSwiftDashSDK:phrase];

    // SwiftDashSDK SPV is started by SwiftDashSDKWalletCreator after the
    // imported wallet record is committed to SwiftData (see
    // SwiftDashSDKWalletCreator.swift). No DashSync startSync needed —
    // DashSync's parallel SPV was retired in M6.
}

- (void)importWalletIntoSwiftDashSDK:(NSString *)phrase {
    if (phrase.length == 0) {
        return;
    }

    NSString *pin = [DWAuthenticationService shared].currentPin;
    if (pin.length == 0) {
        return;
    }

    DWSwiftDashSDKNetwork network;
    if (DWWalletEnvironment.isMainnet) {
        network = DWSwiftDashSDKNetworkMainnet;
    }
    else if (DWWalletEnvironment.isTestnet) {
        network = DWSwiftDashSDKNetworkTestnet;
    }
    else {
        return; // devnet/regtest unsupported in v1
    }

    [DWSwiftDashSDKWalletCreator importWalletWithMnemonic:phrase pin:pin network:network];
}

@end

NS_ASSUME_NONNULL_END

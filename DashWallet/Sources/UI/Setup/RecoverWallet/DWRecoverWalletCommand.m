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

#import "DWEnvironment.h"
#import "DWGlobalOptions.h"

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

    [DWGlobalOptions sharedInstance].recoveringWallet = YES;

    // START_SYNC_ENTRY_POINT
    [[DWEnvironment sharedInstance].currentChainManager.peerManager connect];
}

@end

NS_ASSUME_NONNULL_END

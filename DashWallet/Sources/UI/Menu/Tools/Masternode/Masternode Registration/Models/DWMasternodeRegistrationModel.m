//
//  Created by Sam Westrich
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

#import "DWMasternodeRegistrationModel.h"

@interface DWMasternodeRegistrationModel ()

@property (nonatomic, strong) DSWallet *wallet;
@property (readonly, nonatomic, strong) DSAuthenticationKeysDerivationPath *ownerDerivationPath;
@property (readonly, nonatomic, strong) DSAuthenticationKeysDerivationPath *votingDerivationPath;
@property (readonly, nonatomic, strong) DSAuthenticationKeysDerivationPath *operatorDerivationPath;

@end

@implementation DWMasternodeRegistrationModel

- (instancetype)initForWallet:(DSWallet *)wallet {
    self = [super init];
    if (self) {
        _wallet = wallet;
        _port = wallet.chain.standardPort;
        DSDerivationPathFactory *factory = [DSDerivationPathFactory sharedInstance];
        _ownerDerivationPath = [factory providerOwnerKeysDerivationPathForWallet:wallet];
        _votingDerivationPath = [factory providerVotingKeysDerivationPathForWallet:wallet];
        _operatorDerivationPath = [factory providerOperatorKeysDerivationPathForWallet:wallet];
    }
    return self;
}

- (void)setOperatorPublicKeyIndex:(uint32_t)operatorPublicKeyIndex {
    _operatorPublicKeyIndex = operatorPublicKeyIndex;
    _operatorPublicKeyData = [self.operatorDerivationPath publicKeyDataAtIndex:operatorPublicKeyIndex];
}

- (void)setOwnerPublicKeyIndex:(uint32_t)ownerPublicKeyIndex {
    _ownerPublicKeyIndex = ownerPublicKeyIndex;
    _ownerPublicKeyData = [self.ownerDerivationPath publicKeyDataAtIndex:ownerPublicKeyIndex];
}

- (void)setVotingPublicKeyIndex:(uint32_t)votingPublicKeyIndex {
    _votingPublicKeyIndex = votingPublicKeyIndex;
    _votingPublicKeyData = [self.votingDerivationPath publicKeyDataAtIndex:votingPublicKeyIndex];
}

- (void)setOperatorPublicKeyData:(NSData *)operatorPublicKeyData {
    _operatorPublicKeyData = operatorPublicKeyData;
    NSString *address = [DSKey addressWithPublicKeyData:operatorPublicKeyData forChain:_wallet.chain];
    _operatorPublicKeyIndex = [self.operatorDerivationPath indexOfKnownAddress:address];
}

- (void)setOwnerPublicKeyData:(NSData *)ownerPublicKeyData {
    _ownerPublicKeyData = ownerPublicKeyData;
    NSString *address = [DSKey addressWithPublicKeyData:ownerPublicKeyData forChain:_wallet.chain];
    _ownerPublicKeyIndex = [self.ownerDerivationPath indexOfKnownAddress:address];
}

- (void)setVotingPublicKeyData:(NSData *)votingPublicKeyData {
    _votingPublicKeyData = votingPublicKeyData;
    NSString *address = [DSKey addressWithPublicKeyData:votingPublicKeyData forChain:_wallet.chain];
    _votingPublicKeyIndex = [self.votingDerivationPath indexOfKnownAddress:address];
}


@end

//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import "DWExtendedPublicKeysModel.h"

#import "DWEnvironment.h"

#import "DWDerivationPathKeysItemObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWExtendedPublicKeysModel ()

@end

NS_ASSUME_NONNULL_END

@implementation DWExtendedPublicKeysModel

- (instancetype)init {
    self = [super init];
    if (self) {
        DSAccount *currentAccount = [DWEnvironment sharedInstance].currentAccount;
        _derivationPaths = [currentAccount.fundDerivationPaths copy];
    }
    return self;
}

- (id<DWDerivationPathKeysItem>)itemFor:(DSDerivationPath *)derivationPath {
    DWDerivationPathKeysItemObject *item = [[DWDerivationPathKeysItemObject alloc] init];

    if ([derivationPath isKindOfClass:DSIncomingFundsDerivationPath.class]) {
        item.title = [(DSIncomingFundsDerivationPath *)derivationPath contactDestinationBlockchainIdentity].currentDashpayUsername;
    }
    else {
        item.title = [derivationPath referenceName];
    }

    item.detail = [derivationPath serializedExtendedPublicKey];

    return item;
}

@end

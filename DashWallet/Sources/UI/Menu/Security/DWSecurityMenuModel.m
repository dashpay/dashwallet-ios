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

#import "DWSecurityMenuModel.h"

#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DWSecurityMenuModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _hasTouchID = [DSAuthenticationManager sharedInstance].touchIdEnabled;
        _hasFaceID = [DSAuthenticationManager sharedInstance].faceIdEnabled;
    }
    return self;
}

- (NSString *)biometricAuthSpendingLimit {
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    DSChainsManager *chainsManager = [DSChainsManager sharedInstance];

    return [priceManager stringForDashAmount:chainsManager.spendingLimit];
}

@end

NS_ASSUME_NONNULL_END

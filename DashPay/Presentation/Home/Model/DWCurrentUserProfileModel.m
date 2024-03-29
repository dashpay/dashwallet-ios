//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWCurrentUserProfileModel.h"

#import "DWEnvironment.h"
// if MOCK_DASHPAY
#import "DWDashPayConstants.h"
#import "DWGlobalOptions.h"

@interface DWCurrentUserProfileModel ()

@property (nonatomic, assign) DWCurrentUserProfileModelState state;

@end

@implementation DWCurrentUserProfileModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _updateModel = [[DWDPUpdateProfileModel alloc] init];
    }
    return self;
}

- (DSBlockchainIdentity *)blockchainIdentity {
    if (MOCK_DASHPAY) {
        NSString *username = [DWGlobalOptions sharedInstance].dashpayUsername;
        
        if (username != nil) {
            return [[DWEnvironment sharedInstance].currentWallet createBlockchainIdentityForUsername:username];
        }
    }
    
    return [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;
}

- (void)update {
    if (self.blockchainIdentity == nil) {
        self.state = DWCurrentUserProfileModel_None;
        return;
    }

    if (self.state == DWCurrentUserProfileModel_Loading) {
        return;
    }

    self.state = DWCurrentUserProfileModel_Loading;
    
    if (MOCK_DASHPAY) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.state = DWCurrentUserProfileModel_Done;
        });
        
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self.blockchainIdentity fetchProfileWithCompletion:^(BOOL success, NSError *_Nonnull error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        strongSelf.state = success ? DWCurrentUserProfileModel_Done : DWCurrentUserProfileModel_Error;
    }];
}

@end

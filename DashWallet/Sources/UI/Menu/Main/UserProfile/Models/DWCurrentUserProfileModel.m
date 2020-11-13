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
    return [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;
}

- (void)update {
    if (self.state == DWCurrentUserProfileModel_Loading) {
        return;
    }

    self.state = DWCurrentUserProfileModel_Loading;

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

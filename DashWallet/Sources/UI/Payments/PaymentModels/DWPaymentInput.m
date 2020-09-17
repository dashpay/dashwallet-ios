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

#import "DWPaymentInput+Private.h"

#import "DWDPUserObject.h"
#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DWPaymentInput

- (instancetype)initWithSource:(DWPaymentInputSource)source {
    self = [super init];
    if (self) {
        _source = source;
    }
    return self;
}

- (void)dealloc {
    [self.strangerRequest cancel];
}

- (nullable NSString *)userDetails {
    NSString *result = nil;
    if (self.request) {
        result = self.request.string;
    }
    else if (self.protocolRequest) {
        result = (self.protocolRequest.details.memo ?: self.protocolRequest.details.paymentURL) ?: @"<?>";
    }

    NSString *prefixToRemove = @"dash:";
    if ([result hasPrefix:prefixToRemove]) {
        result = [result substringFromIndex:prefixToRemove.length];
    }

    return result;
}

- (void)fetchStrangerBlockchainIdentity:(NSString *)username {
    DSIdentitiesManager *manager = [DWEnvironment sharedInstance].currentChainManager.identitiesManager;
    __weak typeof(self) weakSelf = self;
    self.strangerRequest = [manager
        searchIdentityByDashpayUsername:username
                         withCompletion:^(BOOL succeess, DSBlockchainIdentity *_Nullable blockchainIdentity, NSError *_Nullable error) {
                             __strong typeof(weakSelf) strongSelf = weakSelf;
                             if (!strongSelf) {
                                 return;
                             }

                             NSAssert([NSThread isMainThread], @"Main thread is assumed here");

                             if (blockchainIdentity != nil) {
                                 strongSelf.strangerUserItem = [[DWDPUserObject alloc] initWithBlockchainIdentity:blockchainIdentity];
                             }
                         }];
}

@end

NS_ASSUME_NONNULL_END

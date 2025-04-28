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

#import "DWDPNewIncomingRequestNotificationObject.h"

#import <DashSync/DashSync.h>

#import "dashwallet-Swift.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

@implementation DWDPNewIncomingRequestNotificationObject

@synthesize subtitle = _subtitle;
@synthesize date = _date;

- (instancetype)initWithFriendRequestEntity:(DSFriendRequestEntity *)friendRequestEntity
                                   identity:(DSIdentity *)identity {
    self = [super initWithFriendRequestEntity:friendRequestEntity identity:identity];
    if (self) {
        _date = [NSDate dateWithTimeIntervalSince1970:friendRequestEntity.timestamp];
    }
    return self;
}

- (NSString *)subtitle {
    if (_subtitle == nil) {
        if (MOCK_DASHPAY) {
            _subtitle = [[DWDateFormatter sharedInstance] shortStringFromDate:[NSDate now]];
        }
        else {
            _subtitle = [[DWDateFormatter sharedInstance] shortStringFromDate:self.date];
        }
    }
    return _subtitle;
}

@end
#pragma clang diagnostic pop

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

#import "DWDPNotificationItemsFactory.h"

#import "DWDPEstablishedContactNotificationObject.h"
#import "DWDPIgnoredRequestNotificationObject.h"
#import "DWDPIncomingRequestNotificationObject.h"

@implementation DWDPNotificationItemsFactory

- (id<DWDPBasicItem, DWDPFriendRequestBackedItem>)itemForFriendRequestEntity:(DSFriendRequestEntity *)entity {
    // TODO: impl
    const BOOL isIgnored = arc4random() % 2 == 0;
    if (isIgnored) {
        return [[DWDPIgnoredRequestNotificationObject alloc] initWithFriendRequestEntity:entity];
    }
    else {
        return [[DWDPIncomingRequestNotificationObject alloc] initWithFriendRequestEntity:entity];
    }
}

- (id<DWDPBasicItem, DWDPDashpayUserBackedItem>)itemForDashpayUserEntity:(DSDashpayUserEntity *)entity {
    return [[DWDPEstablishedContactNotificationObject alloc] initWithDashpayUserEntity:entity];
}

@end
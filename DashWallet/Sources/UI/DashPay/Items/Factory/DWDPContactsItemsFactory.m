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

#import "DWDPContactsItemsFactory.h"

#import "DWDPContactObject.h"
#import "DWDPIgnoredRequestObject.h"
#import "DWDPIncomingRequestObject.h"

@implementation DWDPContactsItemsFactory

- (id<DWDPBasicItem, DWDPFriendRequestBackedItem>)itemForFriendRequestEntity:(DSFriendRequestEntity *)entity {
    // TODO: impl case `if entity.isIgnored`
    return [[DWDPIncomingRequestObject alloc] initWithFriendRequestEntity:entity];
}

- (id<DWDPBasicItem, DWDPDashpayUserBackedItem>)itemForDashpayUserEntity:(DSDashpayUserEntity *)entity {
    return [[DWDPContactObject alloc] initWithDashpayUserEntity:entity];
}

@end

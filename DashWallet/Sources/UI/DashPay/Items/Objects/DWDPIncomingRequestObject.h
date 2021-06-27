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

#import "DWDPFriendRequestBackedItem.h"
#import "DWDPIncomingRequestItem.h"

NS_ASSUME_NONNULL_BEGIN

@class DSFriendRequestEntity;

@interface DWDPIncomingRequestObject : NSObject <DWDPIncomingRequestItem, DWDPFriendRequestBackedItem>

@property (readonly, nullable, strong, nonatomic) DSFriendRequestEntity *friendRequestEntity;

- (instancetype)initWithFriendRequestEntity:(DSFriendRequestEntity *)friendRequestEntity
                         blockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithBlockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

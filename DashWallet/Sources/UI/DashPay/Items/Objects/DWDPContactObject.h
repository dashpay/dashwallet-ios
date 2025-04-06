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

#import "DWDPBasicUserItem.h"
#import "DWDPDashpayUserBackedItem.h"

NS_ASSUME_NONNULL_BEGIN

@class DSDashpayUserEntity;

@interface DWDPContactObject : NSObject <DWDPBasicUserItem, DWDPDashpayUserBackedItem>

@property (readonly, nonatomic, strong) DSDashpayUserEntity *userEntity;

@property (nonatomic, strong) NSString *username;
@property (nonatomic, strong) DSIdentity *identity;

- (instancetype)initWithDashpayUserEntity:(DSDashpayUserEntity *)userEntity;

@end

NS_ASSUME_NONNULL_END

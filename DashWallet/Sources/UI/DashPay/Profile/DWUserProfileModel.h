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

#import <Foundation/Foundation.h>

#import <CoreData/CoreData.h>
#import <DashSync/DSBlockchainIdentity.h>

#import "DWDPBasicItem.h"
#import "DWDPBlockchainIdentityBackedItem.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DWUserProfileModelState) {
    DWUserProfileModelState_None,
    DWUserProfileModelState_Loading,
    DWUserProfileModelState_Error,
    DWUserProfileModelState_Done,
};

@class DWUserProfileModel;

@protocol DWUserProfileModelDelegate <NSObject>

- (void)userProfileModelDidUpdateState:(DWUserProfileModel *)model;

@end

@interface DWUserProfileModel : NSObject

@property (readonly, nonatomic, strong) id<DWDPBasicItem> item;
@property (readonly, nonatomic, assign) DWUserProfileModelState state;
@property (readonly, nonatomic, copy) NSString *username;
@property (readonly, nonatomic, assign) DSBlockchainIdentityFriendshipStatus friendshipStatus;

@property (nullable, nonatomic, weak) id<DWUserProfileModelDelegate> delegate;

- (void)update;

- (void)sendContactRequest;
- (void)acceptContactRequest;

- (instancetype)initWithItem:(id<DWDPBasicItem>)item;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

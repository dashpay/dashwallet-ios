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

#import "DWMainMenuModel.h"
#import "DWEnvironment.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWMainMenuItemImpl : NSObject <DWMainMenuItem>

@end

@implementation DWMainMenuItemImpl

@synthesize type = _type;

- (instancetype)initWithType:(DWMainMenuItemType)type {
    self = [super init];
    if (self) {
        _type = type;
    }
    return self;
}

@end

#pragma mark -

@implementation DWMainMenuModel

- (instancetype)initWithInvitesEnabled:(BOOL)enabled votingEnabled:(BOOL)votingEnabled {
    self = [super init];
    if (self) {
        NSMutableArray<id<DWMainMenuItem>> *items = [NSMutableArray array];

        if (enabled) {
            [items addObject:[[DWMainMenuItemImpl alloc] initWithType:DWMainMenuItemType_Invite]];
        }

        if ([[DWEnvironment sharedInstance].currentChain isMainnet]) {
            [items addObjectsFromArray:@[ [[DWMainMenuItemImpl alloc] initWithType:DWMainMenuItemType_BuySellDash] ]];
        }

        [items addObjectsFromArray:@[
            [[DWMainMenuItemImpl alloc] initWithType:DWMainMenuItemType_Explore],
            [[DWMainMenuItemImpl alloc] initWithType:DWMainMenuItemType_Security],
            [[DWMainMenuItemImpl alloc] initWithType:DWMainMenuItemType_Settings],
            [[DWMainMenuItemImpl alloc] initWithType:DWMainMenuItemType_Tools]
        ]];

        if (votingEnabled) {
            [items addObjectsFromArray:@[ [[DWMainMenuItemImpl alloc] initWithType:DWMainMenuItemType_Voting] ]];
        }

        [items addObjectsFromArray:@[ [[DWMainMenuItemImpl alloc] initWithType:DWMainMenuItemType_Support] ]];
        _items = items;
    }
    return self;
}

@end

NS_ASSUME_NONNULL_END

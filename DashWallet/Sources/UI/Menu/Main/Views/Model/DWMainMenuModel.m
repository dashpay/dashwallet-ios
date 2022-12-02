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

- (instancetype)init {
    self = [super init];
    if (self) {
        if ([[DWEnvironment sharedInstance].currentChain isMainnet]) {
            _items = [DWMainMenuModel allItems];
        }
        else {
            _items = [DWMainMenuModel testnetItems];
        }
    }
    return self;
}

+ (NSArray *)allItems {
    static NSArray *items;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        items = @[
            [[DWMainMenuItemImpl alloc] initWithType:DWMainMenuItemType_BuySellDash],
            [[DWMainMenuItemImpl alloc] initWithType:DWMainMenuItemType_Explore],
            [[DWMainMenuItemImpl alloc] initWithType:DWMainMenuItemType_Security],
            [[DWMainMenuItemImpl alloc] initWithType:DWMainMenuItemType_Settings],
            [[DWMainMenuItemImpl alloc] initWithType:DWMainMenuItemType_Tools],
            [[DWMainMenuItemImpl alloc] initWithType:DWMainMenuItemType_Support],
        ];
    });
    return items;
}

+ (NSArray *)testnetItems {
    static NSArray *items;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        items = @[
            [[DWMainMenuItemImpl alloc] initWithType:DWMainMenuItemType_Explore],
            [[DWMainMenuItemImpl alloc] initWithType:DWMainMenuItemType_Security],
            [[DWMainMenuItemImpl alloc] initWithType:DWMainMenuItemType_Settings],
            [[DWMainMenuItemImpl alloc] initWithType:DWMainMenuItemType_Tools],
            [[DWMainMenuItemImpl alloc] initWithType:DWMainMenuItemType_Support],
        ];
    });
    return items;
}

@end

NS_ASSUME_NONNULL_END

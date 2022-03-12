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

#import "DWShortcutsModel.h"

#import "DWGlobalOptions.h"
#import "DWShortcutAction.h"
#import "DevicesCompatibility.h"

NS_ASSUME_NONNULL_BEGIN

static NSInteger MAX_SHORTCUTS_COUNT = 4;

@interface DWShortcutsModel ()

@property (strong, nonatomic) NSMutableArray<DWShortcutAction *> *mutableItems;
@property (nullable, nonatomic, weak) id<DWShortcutsModelDataSource> dataSource;

@end

@implementation DWShortcutsModel

+ (NSSet<NSString *> *)keyPathsForValuesAffectingValueForKey:(NSString *)key {
    DWShortcutsModel *obj = nil;
    NSSet *keyPaths = @{
        DW_KEYPATH(obj, items) : [NSSet setWithObject:DW_KEYPATH(obj, mutableItems)],
    }[key];
    return keyPaths ?: [super keyPathsForValuesAffectingValueForKey:key];
}

- (instancetype)initWithDataSource:(id<DWShortcutsModelDataSource>)dataSource {
    self = [super init];
    if (self) {
        _dataSource = dataSource;
        [self reloadShortcuts];
    }
    return self;
}

- (void)dealloc {
    DSLog(@"☠️ %@", NSStringFromClass(self.class));
}

- (NSArray<DWShortcutAction *> *)items {
    return [self.mutableItems copy];
}

- (void)reloadShortcuts {
    DWGlobalOptions *options = [DWGlobalOptions sharedInstance];
    NSArray<NSNumber *> *shortcutsSettings = options.shortcuts;

    if (shortcutsSettings) {
        self.mutableItems = [self.class userShortcuts];
    }
    else {
        const BOOL isShowingCreateUserName = [self.dataSource shouldShowCreateUserNameButton];
        self.mutableItems = [self.class defaultShortcutsShowingCreateUserName:isShowingCreateUserName];
    }
}

#pragma mark - Private

+ (NSMutableArray<DWShortcutAction *> *)defaultShortcutsShowingCreateUserName:(BOOL)isShowingCreateUserName {
    DWGlobalOptions *options = [DWGlobalOptions sharedInstance];

    NSMutableArray<DWShortcutAction *> *mutableItems = [NSMutableArray array];

    isShowingCreateUserName = NO;

    if (isShowingCreateUserName) {
        [mutableItems addObject:[DWShortcutAction action:DWShortcutActionType_CreateUsername]];
    }

    const BOOL walletNeedsBackup = options.walletNeedsBackup;
    const BOOL userHasBalance = options.userHasBalance;
    if (walletNeedsBackup) {
        [mutableItems addObject:[DWShortcutAction action:DWShortcutActionType_SecureWallet]];
    }

    if (userHasBalance) {
        [mutableItems addObject:[DWShortcutAction action:DWShortcutActionType_ScanToPay]];
    }

    [mutableItems addObject:[DWShortcutAction action:DWShortcutActionType_Receive]];

    if (userHasBalance) {
        [mutableItems addObject:[DWShortcutAction action:DWShortcutActionType_PayToAddress]];
    }
    else {
        [mutableItems addObject:[DWShortcutAction action:DWShortcutActionType_BuySellDash]];
    }

    //    if (!IS_IPHONE_5_OR_LESS) {
    //        [mutableItems addObject:[DWShortcutAction action:DWShortcutActionType_Explore]];
    //    }

    return mutableItems;
}

+ (NSMutableArray<DWShortcutAction *> *)userShortcuts {
    DWGlobalOptions *options = [DWGlobalOptions sharedInstance];
    NSAssert(options.walletNeedsBackup == NO,
             @"User not allowed to configure shortcuts if backup is not done");
    NSParameterAssert(options.shortcuts);

    const BOOL userHasBalance = options.userHasBalance;

    NSArray<NSNumber *> *shortcutsSettings = options.shortcuts;

    NSMutableArray<DWShortcutAction *> *mutableItems = [NSMutableArray array];

    const BOOL walletNeedsBackup = options.walletNeedsBackup;

    if (walletNeedsBackup) {
        [mutableItems addObject:[DWShortcutAction action:DWShortcutActionType_SecureWallet]];
    }

    if (userHasBalance) {
        [mutableItems addObject:[DWShortcutAction action:DWShortcutActionType_ScanToPay]];
    }

    [mutableItems addObject:[DWShortcutAction action:DWShortcutActionType_Receive]];

    if (userHasBalance) {
        [mutableItems addObject:[DWShortcutAction action:DWShortcutActionType_PayToAddress]];
    }
    else {
        [mutableItems addObject:[DWShortcutAction action:DWShortcutActionType_BuySellDash]];
    }

    //    if (!IS_IPHONE_5_OR_LESS) {
    //        [mutableItems addObject:[DWShortcutAction action:DWShortcutActionType_Explore]];
    //    }


    return mutableItems;
}


@end

NS_ASSUME_NONNULL_END

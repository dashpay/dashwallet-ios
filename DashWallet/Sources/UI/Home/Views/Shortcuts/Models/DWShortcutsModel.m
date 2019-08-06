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

#import "DWShortcutAction.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWShortcutsModel ()

@property (strong, nonatomic) NSMutableArray<DWShortcutAction *> *mutableItems;

@end

@implementation DWShortcutsModel

- (instancetype)init {
    self = [super init];
    if (self) {
        NSMutableArray<DWShortcutAction *> *mutableItems = [NSMutableArray array];

        // TODO: get from settings

        for (NSUInteger i = 1; i <= 11; i++) {
            [mutableItems addObject:[DWShortcutAction action:i]];
        }
        [mutableItems addObject:[DWShortcutAction action:DWShortcutActionType_AddShortcut]];

        //        [mutableItems addObject:[DWShortcutAction action:DWShortcutActionType_ScanToPay]];
        //        [mutableItems addObject:[DWShortcutAction action:DWShortcutActionType_PayToAddress]];
        //        [mutableItems addObject:[DWShortcutAction action:DWShortcutActionType_BuySellDash]];
        //        [mutableItems addObject:[DWShortcutAction action:DWShortcutActionType_SyncNow]];

        _mutableItems = mutableItems;
    }
    return self;
}

- (NSArray<DWShortcutAction *> *)items {
    return [self.mutableItems copy];
}

@end

NS_ASSUME_NONNULL_END

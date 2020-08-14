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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Values of DWShortcutActionType are stored in NSUserDefaults
// Be careful when adding/modifying this enum
// When adding a new action type, update the validation logic in DWShortcutsModel
typedef NS_ENUM(NSInteger, DWShortcutActionType) {
    DWShortcutActionType_SecureWallet = 1,
    DWShortcutActionType_ScanToPay = 2,
    DWShortcutActionType_PayToAddress = 3,
    DWShortcutActionType_BuySellDash = 4,
    DWShortcutActionType_SyncNow = 5,
    DWShortcutActionType_PayWithNFC = 6,
    DWShortcutActionType_LocalCurrency = 7,
    DWShortcutActionType_ImportPrivateKey = 8,
    DWShortcutActionType_SwitchToTestnet = 9,
    DWShortcutActionType_SwitchToMainnet = 10,
    DWShortcutActionType_ReportAnIssue = 11,
    DWShortcutActionType_CreateUsername = 12,
    DWShortcutActionType_AddShortcut = 1000,
};

@interface DWShortcutAction : NSObject

@property (readonly, nonatomic, assign) DWShortcutActionType type;
@property (readonly, nonatomic, assign) BOOL enabled;

+ (instancetype)action:(DWShortcutActionType)type;
+ (instancetype)action:(DWShortcutActionType)type enabled:(BOOL)enabled;

- (instancetype)initWithType:(DWShortcutActionType)type enabled:(BOOL)enabled;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

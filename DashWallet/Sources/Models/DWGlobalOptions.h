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

#import <DashSync/DSDynamicOptions.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A centralized place of User Defaults shared among several parts of the app
 
 To add a new option: add a property with UsedDefaults-supported type and mark it as @dynamic
 in the implementation
 */
@interface DWGlobalOptions : DSDynamicOptions

@property (nonatomic, assign) BOOL walletNeedsBackup;
@property (nullable, nonatomic, strong) NSDate *balanceChangedDate;
@property (nonatomic, assign) BOOL walletBackupReminderWasShown;

@property (nonatomic, assign) BOOL biometricAuthConfigured;
@property (nonatomic, assign) BOOL biometricAuthEnabled;

@property (nullable, nonatomic, copy) NSArray<NSNumber *> *shortcuts;

// Non-stored options

- (NSTimeInterval)autoLockAppInterval;

// Methods

- (void)restoreToDefaults;

+ (instancetype)sharedInstance;

@end

NS_ASSUME_NONNULL_END

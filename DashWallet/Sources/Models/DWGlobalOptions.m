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

#import "DWGlobalOptions.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWGlobalOptions

@dynamic walletNeedsBackup;
@dynamic balanceChangedDate;
@dynamic walletBackupReminderWasShown;
@dynamic biometricAuthConfigured;
@dynamic biometricAuthEnabled;
@dynamic shortcuts;

#pragma mark - Init

- (instancetype)init {
    NSDictionary *defaults = @{
        @"walletNeedsBackup" : @YES,
    };

    self = [super initWithUserDefaults:nil defaults:defaults];
    return self;
}

+ (instancetype)sharedInstance {
    static DWGlobalOptions *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    return _sharedInstance;
}

#pragma mark - DSDynamicOptions

- (NSString *)defaultsKeyForPropertyName:(NSString *)propertyName {
    return [NSString stringWithFormat:@"DW_GLOB_%@", propertyName];
}

#pragma mark - Non-stored options

- (NSTimeInterval)autoLockAppInterval {
    // TODO: for debugging/testing purposes. set to 60
    return 5.0;
}

#pragma mark - Methods

- (void)restoreToDefaults {
    self.walletNeedsBackup = YES;
    self.balanceChangedDate = nil;
    self.walletBackupReminderWasShown = NO;
    self.shortcuts = nil;
}

@end

NS_ASSUME_NONNULL_END

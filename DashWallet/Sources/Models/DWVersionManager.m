//
//  DWVersionManager.m
//  dashwallet
//
//  Created by Sam Westrich on 11/2/18.
//  Copyright © 2019 Dash Core. All rights reserved.
//

#import "DWVersionManager.h"

#import "DWGlobalOptions.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWVersionManager

+ (instancetype)sharedInstance {
    static DWVersionManager *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    return _sharedInstance;
}

- (void)migrateUserDefaults {
    NSString *const oldWalletNeedsBackupKey = @"WALLET_NEEDS_BACKUP";
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    if ([userDefaults objectForKey:oldWalletNeedsBackupKey]) {
        BOOL walletNeedsBackup = [userDefaults boolForKey:oldWalletNeedsBackupKey];
        [DWGlobalOptions sharedInstance].walletNeedsBackup = walletNeedsBackup;

        [userDefaults removeObjectForKey:oldWalletNeedsBackupKey];
    }
}

@end

NS_ASSUME_NONNULL_END

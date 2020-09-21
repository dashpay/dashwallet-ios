//
//  DWDataMigrationManager.m
//  dashwallet
//
//  Created by Andrew Podkovyrin on 08/11/2018.
//  Copyright © 2019 Dash Core. All rights reserved.
//

#import "DWDataMigrationManager.h"

#import "DWEnvironment.h"

#import <DashSync/DSAccountEntity+CoreDataClass.h>
#import <DashSync/DSChain.h>
#import <DashSync/DSChainEntity+CoreDataClass.h>
#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DWDataMigrationManager

+ (instancetype)sharedInstance {
    static DWDataMigrationManager *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _shouldMigrate = [DSCoreDataMigrator requiresMigration];
    }
    return self;
}

- (BOOL)isMigrationSuccessful {
    return YES;
}

- (void)migrate:(void (^)(BOOL completed))completion {
    NSAssert([NSThread isMainThread], @"Main thread is assumed here");

    if (![DSCoreDataMigrator requiresMigration]) {
        completion(YES);
        return;
    }

    [DSCoreDataMigrator performMigrationWithCompletionQueue:dispatch_get_main_queue()
                                                 completion:^{
                                                     completion(YES);
                                                 }];
}

@end

NS_ASSUME_NONNULL_END

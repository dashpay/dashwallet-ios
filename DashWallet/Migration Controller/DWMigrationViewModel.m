//
//  DWMigrationViewModel.m
//  dashwallet
//
//  Created by Andrew Podkovyrin on 10/11/2018.
//  Copyright © 2018 Dash Core. All rights reserved.
//

#import "DWMigrationViewModel.h"

#import "DWDataMigrationManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWMigrationViewModel ()

@property (assign, nonatomic) DWMigrationViewModelState state;

@end

@implementation DWMigrationViewModel

- (instancetype)initWithLaunchOptions:(NSDictionary *)launchOptions {
    self = [super init];
    if (self) {
        _deferredLaunchOptions = [launchOptions copy];
        _applicationCrashedDuringLastMigration = [DWDataMigrationManager sharedInstance].migrationSuccessful;
    }
    return self;
}

- (void)startMigration {
    if (self.state != DWMigrationViewModelStateNone) {
        return;
    }

    self.state = DWMigrationViewModelStateInProgress;

#ifdef DEBUG
    NSDate *startTime = [NSDate date];
#endif /* DEBUG */

    __weak __typeof__(self) weakSelf = self;
    [[DWDataMigrationManager sharedInstance] migrate:^(BOOL completed) {
        __strong __typeof__(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

#ifdef DEBUG
        NSLog(@"⏲ Migration time: %f", -[startTime timeIntervalSinceNow]);
#endif /* DEBUG */

        strongSelf.state = DWMigrationViewModelStateDone;
    }];
}

- (void)cancelMigration {
    [[DWDataMigrationManager sharedInstance] destroyOldPersistentStore];
    self.state = DWMigrationViewModelStateDone;
}

- (void)cancelMigrationAndRescanBlockchain {
    [[DWDataMigrationManager sharedInstance] destroyOldPersistentStore];
    self.state = DWMigrationViewModelStateDoneAndRescan;
}

@end

NS_ASSUME_NONNULL_END

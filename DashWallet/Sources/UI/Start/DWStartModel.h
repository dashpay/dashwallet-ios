//
//  DWStartModel.h
//  dashwallet
//
//  Created by Andrew Podkovyrin on 10/11/2018.
//  Copyright © 2019 Dash Core. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, DWStartModelState) {
    DWStartModelStateNone,
    DWStartModelStateInProgress,
    DWStartModelStateDone,
    DWStartModelStateDoneAndRescan,
};

@interface DWStartModel : NSObject

@property (readonly, assign, nonatomic) DWStartModelState state;
@property (readonly, copy, nonatomic) NSDictionary *deferredLaunchOptions;

- (instancetype)initWithLaunchOptions:(NSDictionary *)launchOptions;

// Migration:

@property (readonly, assign, nonatomic) BOOL shouldMigrate;
@property (readonly, assign, nonatomic) BOOL applicationCrashedDuringLastMigration;
- (void)startMigration;
- (void)cancelMigration;
- (void)cancelMigrationAndRescanBlockchain;

- (void)finalizeAsIs;

@end

NS_ASSUME_NONNULL_END

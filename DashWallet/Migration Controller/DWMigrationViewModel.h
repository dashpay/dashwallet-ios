//
//  DWMigrationViewModel.h
//  dashwallet
//
//  Created by Andrew Podkovyrin on 10/11/2018.
//  Copyright © 2018 Dash Core. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, DWMigrationViewModelState) {
    DWMigrationViewModelStateNone,
    DWMigrationViewModelStateInProgress,
    DWMigrationViewModelStateDone,
};

@interface DWMigrationViewModel : NSObject

@property (readonly, assign, nonatomic) DWMigrationViewModelState state;
@property (readonly, copy, nonatomic) NSDictionary *deferredLaunchOptions;

- (instancetype)initWithLaunchOptions:(NSDictionary *)launchOptions;

- (void)startMigration;

- (void)cancelMigration;

@end

NS_ASSUME_NONNULL_END

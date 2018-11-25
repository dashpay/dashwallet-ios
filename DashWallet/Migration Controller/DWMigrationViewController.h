//
//  DWMigrationViewController.h
//  dashwallet
//
//  Created by Andrew Podkovyrin on 10/11/2018.
//  Copyright © 2018 Dash Core. All rights reserved.
//

#import "DWBaseRootViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class DWMigrationViewModel;
@protocol DWMigrationViewControllerDelegate;

@interface DWMigrationViewController : DWBaseRootViewController

@property (strong, nonatomic) DWMigrationViewModel *viewModel;
@property (nullable, weak, nonatomic) id<DWMigrationViewControllerDelegate> delegate;

+ (instancetype)controller;

@end

@protocol DWMigrationViewControllerDelegate <NSObject>

- (void)migrationViewController:(DWMigrationViewController *)controller didFinishWithDeferredLaunchOptions:(NSDictionary *)launchOptions;

@end

NS_ASSUME_NONNULL_END

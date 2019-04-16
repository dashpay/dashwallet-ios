//
//  DWStartViewController.h
//  dashwallet
//
//  Created by Andrew Podkovyrin on 10/11/2018.
//  Copyright © 2019 Dash Core. All rights reserved.
//

#import "DWBaseRootViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class DWStartModel;
@protocol DWStartViewControllerDelegate;

@interface DWStartViewController : DWBaseRootViewController

@property (strong, nonatomic) DWStartModel *viewModel;
@property (nullable, weak, nonatomic) id<DWStartViewControllerDelegate> delegate;

+ (instancetype)controller;

@end

@protocol DWStartViewControllerDelegate <NSObject>

- (void)startViewController:(DWStartViewController *)controller
    didFinishWithDeferredLaunchOptions:(NSDictionary *)launchOptions
                shouldRescanBlockchain:(BOOL)shouldRescanBlockchain;

@end

NS_ASSUME_NONNULL_END

//
//  DWMigrationViewController.m
//  dashwallet
//
//  Created by Andrew Podkovyrin on 10/11/2018.
//  Copyright © 2018 Dash Core. All rights reserved.
//

#import "DWMigrationViewController.h"

#import "DWMigrationViewModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWMigrationViewController ()

@end

@implementation DWMigrationViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"MigrationStoryboard" bundle:nil];
    DWMigrationViewController *controller = [storyboard instantiateInitialViewController];
    return controller;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (BOOL)shouldAutorotate {
    return NO;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSParameterAssert(self.viewModel);

    [self mvvm_observe:@"viewModel.state" with:^(__typeof__(self) self, NSNumber * value) {
        if (self.viewModel.state == DWMigrationViewModelStateDone) {
            [self.delegate migrationViewController:self didFinishWithDeferredLaunchOptions:self.viewModel.deferredLaunchOptions];
        }
    }];
}

- (void)protectedViewDidAppear {
    [super protectedViewDidAppear];
    
    DSVersionManager *dashSyncVersionManager = [DSVersionManager sharedInstance];

    if ([dashSyncVersionManager noOldWallet]) {
        NSAssert(NO, @"keychain is empty but CoreData database exists (it might be inconsistent debug issue)");
        
        [self.viewModel cancelMigration];

        return;
    }

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    [dashSyncVersionManager upgradeExtendedKeysForWallet:wallet chain:[DWEnvironment sharedInstance].currentChain withMessage:NSLocalizedString(@"please enter pin to upgrade wallet", nil) withCompletion:^(BOOL success, BOOL neededUpgrade, BOOL authenticated, BOOL cancelled) {
        if (!success && neededUpgrade && !authenticated) {
            [self forceUpdateWalletAuthentication:cancelled];
        }
        else {
            [self.viewModel startMigration];
        }
    }];
}

@end

NS_ASSUME_NONNULL_END

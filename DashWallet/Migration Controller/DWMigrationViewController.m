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
            [self.delegate migrationViewController:self
                didFinishWithDeferredLaunchOptions:self.viewModel.deferredLaunchOptions
                            shouldRescanBlockchain:NO];
        }
        else if (self.viewModel.state == DWMigrationViewModelStateDoneAndRescan) {
            [self.delegate migrationViewController:self
                didFinishWithDeferredLaunchOptions:self.viewModel.deferredLaunchOptions
                            shouldRescanBlockchain:YES];
        }
    }];
}

- (void)protectedViewDidAppear {
    [super protectedViewDidAppear];

    if (self.viewModel.appWasCrashed) {
        [self performCrashRestoration];
    }
    else {
        [self performMigration];
    }
}

#pragma mark - Private

- (void)performCrashRestoration {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:nil
                         message:NSLocalizedString(@"DashWallet app was crashed since last migration. Rescanning blockchain may solve this issue. It will not affect your funds.", nil)
                  preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancelButton = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"cancel", nil)
                  style:UIAlertActionStyleCancel
                handler:^(UIAlertAction *_Nonnull action) {
                    [self performMigration];
                }];
    UIAlertAction *trustButton = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"Rescan blockchain", nil)
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    [self performRescanBlockchain];
                }];
    [alert addAction:trustButton];
    [alert addAction:cancelButton];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performMigration {
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

- (void)performRescanBlockchain {
    [self.viewModel cancelMigrationAndRescanBlockchain];
}

@end

NS_ASSUME_NONNULL_END

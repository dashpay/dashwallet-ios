//
//  DWMigrationViewController.m
//  dashwallet
//
//  Created by Andrew Podkovyrin on 10/11/2018.
//  Copyright © 2019 Dash Core. All rights reserved.
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

    if (self.viewModel.applicationCrashedDuringLastMigration) {
        [self performCrashRestoration];
    }
    else {
        [self performMigration];
    }
}

- (void)showNewWalletController {
    [self.viewModel cancelMigration];
}

#pragma mark - Private

- (void)performCrashRestoration {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:nil
                         message:NSLocalizedString(@"We have detected that Dashwallet crashed during migration. Rescanning the blockchain will solve this issue or you may try again. Rescanning should preferably be performed on wifi and will take up to half an hour. Your funds will be available once the sync process is complete.", nil)
                  preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *migrateButton = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"try again", nil)
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *_Nonnull action) {
                    [self performMigration];
                }];
    UIAlertAction *rescanButton = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"rescan", nil)
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    [self performRescanBlockchain];
                }];
    [alert addAction:rescanButton];
    [alert addAction:migrateButton];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performMigration {
    DSVersionManager *dashSyncVersionManager = [DSVersionManager sharedInstance];
    if ([dashSyncVersionManager noOldWallet]) {
        [self.viewModel startMigration];
        return;
    }

    DSWallet *wallet = [[DWEnvironment sharedInstance] currentWallet];
    [dashSyncVersionManager upgradeVersion1ExtendedKeysForWallet:wallet chain:[DWEnvironment sharedInstance].currentChain withMessage:NSLocalizedString(@"please enter pin to upgrade wallet", nil) withCompletion:^(BOOL success, BOOL neededUpgrade, BOOL authenticated, BOOL cancelled) {
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

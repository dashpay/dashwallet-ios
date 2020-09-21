//
//  Created by Andrew Podkovyrin
//  Copyright © 2018 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "DWStartViewController.h"

#import "DWEnvironment.h"
#import "DWStartModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWStartViewController ()

@end

@implementation DWStartViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"StartStoryboard" bundle:nil];
    DWStartViewController *controller = [storyboard instantiateInitialViewController];
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

    [self mvvm_observe:@"viewModel.state"
                  with:^(__typeof__(self) self, NSNumber *value) {
                      if (self.viewModel.state == DWStartModelStateDone || self.viewModel.state == DWStartModelStateDoneAndRescan) {
                          // upgrade old keys after migration is done
                          if ([self upgradeOldKeys]) {
                              return;
                          }
                      }

                      if (self.viewModel.state == DWStartModelStateDone) {
                          [self.delegate startViewController:self
                              didFinishWithDeferredLaunchOptions:self.viewModel.deferredLaunchOptions
                                          shouldRescanBlockchain:NO];
                      }
                      else if (self.viewModel.state == DWStartModelStateDoneAndRescan) {
                          [self.delegate startViewController:self
                              didFinishWithDeferredLaunchOptions:self.viewModel.deferredLaunchOptions
                                          shouldRescanBlockchain:YES];
                      }
                  }];
}

- (void)protectedViewDidAppear {
    [super protectedViewDidAppear];

    // prioritize migration over crash reporting
    if (self.viewModel.shouldMigrate) {
        if (self.viewModel.applicationCrashedDuringLastMigration) {
            [self performMigrationCrashRestoration];
        }
        else {
            [self performMigration];
        }
    }
    else {
        NSAssert(NO, @"Internal inconsitency");
        // just continue regular launch in Release
        [self.viewModel finalizeAsIs]; // does nothing
    }
}

- (void)showNewWalletController {
    [self.viewModel cancelMigration];
}

#pragma mark - Private

#pragma mark Migration

- (void)performMigrationCrashRestoration {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:nil
                         message:NSLocalizedString(@"We have detected that Dash Wallet crashed during migration. Rescanning the blockchain will solve this issue or you may try again. Rescanning should preferably be performed on wifi and will take up to half an hour. Your funds will be available once the sync process is complete.", nil)
                  preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *migrateButton = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"Try again", @"An action")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *_Nonnull action) {
                    [self performMigration];
                }];
    UIAlertAction *rescanButton = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"Rescan", @"An action")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    [self performRescanBlockchain];
                }];
    [alert addAction:rescanButton];
    [alert addAction:migrateButton];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performMigration {
    [self.viewModel startMigration];
}

- (BOOL)upgradeOldKeys {
    DSVersionManager *dashSyncVersionManager = [DSVersionManager sharedInstance];
    if ([dashSyncVersionManager noOldWallet]) {
        return NO;
    }

    DSWallet *wallet = [[DWEnvironment sharedInstance] currentWallet];
    [dashSyncVersionManager upgradeVersion1ExtendedKeysForWallet:wallet
                                                           chain:[DWEnvironment sharedInstance].currentChain
                                                     withMessage:NSLocalizedString(@"Please enter PIN to upgrade wallet", nil)
                                                  withCompletion:^(BOOL success, BOOL neededUpgrade, BOOL authenticated, BOOL cancelled) {
                                                      if (!success && neededUpgrade && !authenticated) {
                                                          [self forceUpdateWalletAuthentication:cancelled];
                                                      }
                                                      else {
                                                          [self.viewModel startMigration];
                                                      }
                                                  }];

    return YES;
}

- (void)performRescanBlockchain {
    [self.viewModel cancelMigrationAndRescanBlockchain];
}

@end

NS_ASSUME_NONNULL_END

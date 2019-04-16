//
//  DWStartViewController.m
//  dashwallet
//
//  Created by Andrew Podkovyrin on 10/11/2018.
//  Copyright © 2019 Dash Core. All rights reserved.
//

#import "DWStartViewController.h"

#import <MessageUI/MessageUI.h>

#import "DWStartModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWStartViewController () <MFMailComposeViewControllerDelegate>

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

    [self mvvm_observe:@"viewModel.state" with:^(__typeof__(self) self, NSNumber * value) {
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
    else if (self.viewModel.shouldHandleCrashReports) {
        [self performCrashReportingForced:NO];
    }
    else {
        NSAssert(NO, @"Internal inconsitency");
        // just continue regular launch in Release
        [self.viewModel finalizeCrashReporting]; // does nothing
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
    if (self.viewModel.shouldHandleCrashReports) {
        UIAlertAction *crashReportButton = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"send crash report", nil)
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                        [self performCrashReportingForced:YES];
                    }];
        [alert addAction:crashReportButton];
    }
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

#pragma mark Crash Reporting

- (void)performCrashReportingForced:(BOOL)forced {
    if (forced) {
        if ([MFMailComposeViewController canSendMail]) {
            MFMailComposeViewController *composeController = [[MFMailComposeViewController alloc] init];
            composeController.subject = @"Crash Report"; // non localizable
            [composeController setToRecipients:@[ @"contact@dash.org" ]]; // TODO: fix me
            
            NSString *body = [NSString stringWithFormat:@"%@:\n\n\n\n\n%@",
                              NSLocalizedString(@"Steps to reproduce the crash", nil),
                              [self.viewModel gatherUserDeviceInfo]];
            [composeController setMessageBody:body isHTML:NO];
            
            for (NSString *filepath in [self.viewModel crashReportFiles]) {
                NSData *data = [NSData dataWithContentsOfFile:filepath];
                if (!data) {
                    continue;
                }
                NSString *fileName = filepath.lastPathComponent ?:
                    [NSString stringWithFormat:@"%ld.plcrash", (NSUInteger)[[NSDate date] timeIntervalSince1970]];
                [composeController addAttachmentData:data mimeType:@"application/octet-stream" fileName:fileName];
            }
            
            composeController.mailComposeDelegate = self;
            [self presentViewController:composeController animated:YES completion:nil];
        }
        else {
            UIAlertController *alert = [UIAlertController
                                        alertControllerWithTitle:nil
                                        message:NSLocalizedString(@"Email client is not configured. Please add your email account in Settings", nil)
                                        preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *cancelAction = [UIAlertAction
                                             actionWithTitle:NSLocalizedString(@"cancel", nil)
                                             style:UIAlertActionStyleCancel
                                             handler:^(UIAlertAction *action) {
                                                 [self.viewModel finalizeCrashReporting];
                                             }];
            [alert addAction:cancelAction];
            [self presentViewController:alert animated:YES completion:nil];
        }
        
        return;
    }
    
    [self.viewModel updateLastCrashReportAskDate];
    
    UIAlertController *alert = [UIAlertController
                                alertControllerWithTitle:nil
                                message:NSLocalizedString(@"We have detected that Dashwallet crashed last time. Help us solving this issue by sending an email with crash report data. Your private data WILL NOT be shared.", nil)
                                preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancelAction = [UIAlertAction
                                    actionWithTitle:NSLocalizedString(@"cancel", nil)
                                    style:UIAlertActionStyleCancel
                                    handler:^(UIAlertAction *_Nonnull action) {
                                        [self.viewModel finalizeCrashReporting];
                                    }];
    [alert addAction:cancelAction];
    UIAlertAction *crashReportAction = [UIAlertAction
                                        actionWithTitle:NSLocalizedString(@"send crash report", nil)
                                        style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *action) {
                                            [self performCrashReportingForced:YES];
                                        }];
    [alert addAction:crashReportAction];
    alert.preferredAction = crashReportAction;
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(nullable NSError *)error {
    if (result == MFMailComposeResultSent || result == MFMailComposeResultSaved) {
        [self.viewModel removeCrashReportFiles];
    }
    [self.viewModel finalizeCrashReporting];
    [controller dismissViewControllerAnimated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END

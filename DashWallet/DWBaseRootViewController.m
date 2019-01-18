//
//  DWBaseRootViewController.m
//  dashwallet
//
//  Created by Andrew Podkovyrin on 21/11/2018.
//  Copyright © 2018 Dash Core. All rights reserved.
//

#import "DWBaseRootViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWBaseRootViewController ()

@property (nullable, nonatomic, strong) id protectedObserver;

@end

@implementation DWBaseRootViewController

- (void)dealloc {
    if (self.protectedObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.protectedObserver];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if ([UIApplication sharedApplication].protectedDataAvailable) {
        [self performSelector:@selector(protectedViewDidAppear) withObject:nil afterDelay:0.0];
    }
    else if (!self.protectedObserver) {
        self.protectedObserver = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationProtectedDataDidBecomeAvailable
                                                                                   object:nil
                                                                                    queue:nil
                                                                               usingBlock:^(NSNotification *note) {
                                                                                   [self performSelector:@selector(protectedViewDidAppear) withObject:nil afterDelay:0.0];
                                                                               }];
    }
}

- (void)protectedViewDidAppear {
    if (self.protectedObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.protectedObserver];
    }
    self.protectedObserver = nil;
}

- (void)forceUpdateWalletAuthentication:(BOOL)cancelled {
    UIAlertController *alert;
    if (cancelled) {
        alert = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"Failed wallet update", nil)
                             message:NSLocalizedString(@"You must enter your pin in order to enter dashwallet", nil)
                      preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *exitButton = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"exit", nil)
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                        [[NSNotificationCenter defaultCenter] postNotificationName:DSAppTerminationRequestNotification object:nil];
                    }];
        UIAlertAction *enterButton = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"enter", nil)
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                        [self protectedViewDidAppear];
                    }];
        [alert addAction:exitButton];
        [alert addAction:enterButton]; //ok button should be on the right side as per Apple guidelines, as reset is the less desireable option
    }
    else {
        __block NSUInteger wait = [[DSAuthenticationManager sharedInstance] lockoutWaitTime];
        NSString *waitTime = [NSString waitTimeFromNow:wait];

        alert = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"Failed wallet update", nil)
                             message:[NSString stringWithFormat:NSLocalizedString(@"\ntry again in %@", nil), waitTime]
                      preferredStyle:UIAlertControllerStyleAlert];
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *_Nonnull timer) {
            wait--;
            alert.message = [NSString stringWithFormat:NSLocalizedString(@"\ntry again in %@", nil), [NSString waitTimeFromNow:wait]];
            if (!wait) {
                [timer invalidate];
                [alert dismissViewControllerAnimated:YES completion:^{
                    [self protectedViewDidAppear];
                }];
            }
        }];
        UIAlertAction *resetButton = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"reset", nil)
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                        [timer invalidate];
                        //todo : redo this logic
                        //                                          [manager showResetWalletWithWipeHandler:^{
                        //                                              [self wipeAlert];
                        //                                          } cancelHandler:^{
                        //                                              [self protectedViewDidAppear];
                        //                                          }];
                    }];
        UIAlertAction *exitButton = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"exit", nil)
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                        [[NSNotificationCenter defaultCenter] postNotificationName:DSAppTerminationRequestNotification object:nil];
                    }];
        [alert addAction:resetButton];
        [alert addAction:exitButton]; //ok button should be on the right side as per Apple guidelines, as reset is the less desireable option
    }
    [self presentViewController:alert animated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END

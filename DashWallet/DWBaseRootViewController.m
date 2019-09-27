//
//  DWBaseRootViewController.m
//  dashwallet
//
//  Created by Andrew Podkovyrin on 21/11/2018.
//  Copyright © 2019 Dash Core. All rights reserved.
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

-(void)wipeAlert {
    UIAlertController * wipeAlert = [UIAlertController
                                     alertControllerWithTitle:NSLocalizedString(@"Are you sure?", nil)
                                     message:NSLocalizedString(@"By wiping this device you will no longer have access to funds on this device. This should only be done if you no longer have access to your passphrase and have also forgotten your pin code.",nil)                                             preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* cancelButton = [UIAlertAction
                                   actionWithTitle:NSLocalizedString(@"cancel", nil)
                                   style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction * action) {
                                       [self protectedViewDidAppear];
                                   }];
    UIAlertAction* wipeButton = [UIAlertAction
                                 actionWithTitle:NSLocalizedString(@"wipe", nil)
                                 style:UIAlertActionStyleDestructive
                                 handler:^(UIAlertAction * action) {
                                     [[DSVersionManager sharedInstance] clearKeychainWalletOldData];
                                     [[DWEnvironment sharedInstance] clearAllWallets];
                                     [[NSUserDefaults standardUserDefaults] removeObjectForKey:WALLET_NEEDS_BACKUP_KEY];
                                     [[NSUserDefaults standardUserDefaults] synchronize];
                                     
                                     [self showNewWalletController];
                                 }];
    [wipeAlert addAction:cancelButton];
    [wipeAlert addAction:wipeButton];
    [self presentViewController:wipeAlert animated:YES completion:nil];
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
                                         [[NSNotificationCenter defaultCenter] postNotificationName:DSApplicationTerminationRequestNotification object:nil];
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
        NSString *waitTime = (wait == NSUIntegerMax)?nil:[NSString waitTimeFromNow:wait];
        if ([waitTime isEqualToString:@""]) waitTime = nil;
        alert = [UIAlertController
                 alertControllerWithTitle:NSLocalizedString(@"Failed wallet update", nil)
                 message:waitTime?[NSString stringWithFormat:NSLocalizedString(@"\ntry again in %@", nil), waitTime]:nil
                 preferredStyle:UIAlertControllerStyleAlert];
        NSTimer *timer = nil;
        if (waitTime) {
            timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *_Nonnull timer) {
                wait--;
                alert.message = [NSString stringWithFormat:NSLocalizedString(@"\ntry again in %@", nil), [NSString waitTimeFromNow:wait]];
                if (!wait) {
                    [timer invalidate];
                    [alert dismissViewControllerAnimated:YES completion:^{
                        [self protectedViewDidAppear];
                    }];
                }
            }];
        }
        UIAlertAction *resetButton = [UIAlertAction
                                      actionWithTitle:NSLocalizedString(@"reset", nil)
                                      style:UIAlertActionStyleDefault
                                      handler:^(UIAlertAction *action) {
                                          if (timer) {
                                              [timer invalidate];
                                          }
            
                                            [[DSAuthenticationManager sharedInstance] resetWalletWithWipeHandler:^{
                                                [self wipeAlert];
                                            } completion:^(BOOL success) {
                                                [self protectedViewDidAppear];
                                            }];
                                      }];
        if (waitTime) {
            UIAlertAction *exitButton = [UIAlertAction
                                         actionWithTitle:NSLocalizedString(@"exit", nil)
                                         style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *action) {
                                             [[NSNotificationCenter defaultCenter] postNotificationName:DSApplicationTerminationRequestNotification object:nil];
                                         }];
            [alert addAction:resetButton];
            [alert addAction:exitButton]; //ok button should be on the right side as per Apple guidelines, as reset is the less desireable option
        } else {
            UIAlertAction *wipeButton = [UIAlertAction
                                         actionWithTitle:NSLocalizedString(@"wipe", nil)
                                         style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *action) {
                                             [self wipeAlert];
                                         }];
            [alert addAction:wipeButton];
            [alert addAction:resetButton];
        }
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showNewWalletController {
    UIViewController *a = self.navigationController.presentedViewController;
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    UIViewController * walletCreationViewController = [storyboard instantiateViewControllerWithIdentifier:@"NewWalletNav"];
    if (a) {
        [a dismissViewControllerAnimated:NO completion:^{
            [self presentViewController:walletCreationViewController animated:NO
                             completion:nil];
        }];
    } else {
        [self presentViewController:walletCreationViewController animated:NO
                         completion:nil];
    }
    
}

@end

NS_ASSUME_NONNULL_END

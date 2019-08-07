//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

#import "DWHomeViewController.h"

#import "DWHomeModel.h"
#import "DWHomeView.h"
#import "DWNavigationController.h"
#import "DWShortcutAction.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWHomeViewController () <DWHomeViewDelegate, DWShortcutsActionDelegate>

@property (null_resettable, strong, nonatomic) DWHomeModel *model;

@property (strong, nonatomic) DWHomeView *view;

@end

@implementation DWHomeViewController

@dynamic view;

+ (UIViewController *)controllerEmbededInNavigation {
    DWHomeViewController *controller = [[DWHomeViewController alloc] init];
    DWNavigationController *navigationController =
        [[DWNavigationController alloc] initWithRootViewController:controller];

    return navigationController;
}

- (void)loadView {
    CGRect frame = [UIScreen mainScreen].bounds;
    self.view = [[DWHomeView alloc] initWithFrame:frame];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view.delegate = self;
    self.view.shortcutsDelegate = self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
    [self performJailbreakCheck];

    // TODO: impl migration stuff from protectedViewDidAppear of DWRootViewController
    // TODO: check if wallet is watchOnly and show info about it
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - DWHomeViewDelegate

- (void)homeView:(DWHomeView *)homeView showTxFilter:(UIView *)sender {
    NSString *title = NSLocalizedString(@"Filter Transactions", nil);
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:title
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];
    {
        UIAlertAction *action = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"All", nil)
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *_Nonnull action) {
                        self.model.displayMode = DWHomeTxDisplayMode_All;
                    }];
        [alert addAction:action];
    }

    {
        UIAlertAction *action = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Received", nil)
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *_Nonnull action) {
                        self.model.displayMode = DWHomeTxDisplayMode_Received;
                    }];
        [alert addAction:action];
    }

    {
        UIAlertAction *action = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Sent", nil)
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *_Nonnull action) {
                        self.model.displayMode = DWHomeTxDisplayMode_Sent;
                    }];
        [alert addAction:action];
    }

    {
        UIAlertAction *action = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Cancel", nil)
                      style:UIAlertActionStyleCancel
                    handler:nil];
        [alert addAction:action];
    }

    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = sender;
        alert.popoverPresentationController.sourceRect = sender.bounds;
    }

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - DWShortcutsActionDelegate

- (void)shortcutsView:(UIView *)view didSelectAction:(DWShortcutAction *)action sender:(UIView *)sender {
    NSLog(@">>> ACTION %@", @(action.type));

    // TODO: for debug purposes
    if (action.type == DWShortcutActionType_SyncNow) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"DEBUG MODE"
                                                                       message:@"YOU ARE ABOUT TO ERASE YOUR WALLET!\n\n☠️☠️☠️\n\nYour seed phrase will be erased forever and wallet quit. Run it again to start from scratch."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *ok = [UIAlertAction
            actionWithTitle:@"OK ☠️"
                      style:UIAlertActionStyleDestructive
                    handler:^(UIAlertAction *_Nonnull action) {
                        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
                        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);

                        NSArray *secItemClasses = @[ (__bridge id)kSecClassGenericPassword,
                                                     (__bridge id)kSecClassInternetPassword,
                                                     (__bridge id)kSecClassCertificate,
                                                     (__bridge id)kSecClassKey,
                                                     (__bridge id)kSecClassIdentity ];
                        for (id secItemClass in secItemClasses) {
                            NSDictionary *spec = @{(__bridge id)kSecClass : secItemClass};
                            SecItemDelete((__bridge CFDictionaryRef)spec);
                        }

                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            exit(0);
                        });
                    }];
        [alert addAction:ok];

        UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Please, no 😭" style:UIAlertActionStyleCancel handler:nil];
        [alert addAction:cancel];

        [self presentViewController:alert animated:YES completion:nil];
    }
}

#pragma mark - Private

- (DWHomeModel *)model {
    if (_model == nil) {
        _model = [[DWHomeModel alloc] init];
    }

    return _model;
}

- (void)setupView {
    UIImage *logoImage = [UIImage imageNamed:@"dash_logo"];
    NSParameterAssert(logoImage);
    self.navigationItem.titleView = [[UIImageView alloc] initWithImage:logoImage];

    self.view.model = self.model;
}

- (void)performJailbreakCheck {
    if (!self.model.isJailbroken) {
        return;
    }

    NSString *title = NSLocalizedString(@"WARNING", nil);
    NSString *message = nil;
    UIAlertAction *mainAction = nil;

    if (!self.model.isWalletEmpty) {
        message = NSLocalizedString(@"DEVICE SECURITY COMPROMISED\n"
                                     "Any 'jailbreak' app can access any other app's keychain data "
                                     "(and steal your dash). "
                                     "Wipe this wallet immediately and restore on a secure device.",
                                    nil);
        mainAction = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Wipe", nil)
                      style:UIAlertActionStyleDestructive
                    handler:^(UIAlertAction *action){
                        // TODO: Show wipe wallet screen (to input seed phrase)
                    }];
    }
    else {
        message = NSLocalizedString(@"DEVICE SECURITY COMPROMISED\n"
                                     "Any 'jailbreak' app can access any other app's keychain data "
                                     "(and steal your dash).",
                                    nil);
        mainAction = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Close App", nil)
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                        [[NSNotificationCenter defaultCenter] postNotificationName:DSApplicationTerminationRequestNotification object:nil];
                    }];
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *ignoreAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Ignore", nil)
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [alert addAction:ignoreAction];

    [alert addAction:mainAction];

    [self presentViewController:alert animated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END

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

#import "DWUpholdViewController.h"

#import "DWAlertController.h"
#import "DWUpholdAuthViewController.h"
#import "DWUpholdClient.h"
#import "DWUpholdConstants.h"
#import "DWUpholdLogoutTutorialViewController.h"
#import "DWUpholdMainViewController.h"
#import "SFSafariViewController+DashWallet.h"
#import "UIViewController+DWChildControllers.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdViewController () <DWUpholdAuthViewControllerDelegate, DWUpholdMainViewControllerDelegate, DWUpholdLogoutTutorialViewControllerDelegate>

@end

@implementation DWUpholdViewController

+ (instancetype)controller {
    return [[self alloc] init];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"Uphold", nil);

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(upholdClientUserDidLogoutNotification:)
                                                 name:DWUpholdClientUserDidLogoutNotification
                                               object:nil];

    BOOL authorized = [DWUpholdClient sharedInstance].authorized;
    UIViewController *controller = authorized ? [self mainController] : [self authController];
    [self dw_displayViewController:controller];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [[DWUpholdClient sharedInstance] updateLastAccessDate];
}

#pragma mark - DWUpholdAuthViewControllerDelegate

- (void)upholdAuthViewControllerDidAuthorize:(DWUpholdAuthViewController *)controller {
    UIViewController *toController = [self mainController];
    [self dw_performTransitionToViewController:toController completion:nil];
}

#pragma mark - DWUpholdMainViewControllerDelegate

- (void)upholdMainViewControllerUserDidLogout:(DWUpholdMainViewController *)controller {
    DWUpholdLogoutTutorialViewController *logoutTutorialController = [DWUpholdLogoutTutorialViewController controller];
    logoutTutorialController.delegate = self;
    DWAlertController *alertController = [[DWAlertController alloc] init];
    [alertController setupContentController:logoutTutorialController];
    [alertController setupActions:logoutTutorialController.providedActions];
    alertController.preferredAction = logoutTutorialController.preferredAction;
    [self presentViewController:alertController animated:YES completion:nil];
}

#pragma mark - DWUpholdLogoutTutorialViewControllerDelegate

- (void)upholdLogoutTutorialViewControllerDidCancel:(DWUpholdLogoutTutorialViewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:nil];
}

- (void)upholdLogoutTutorialViewControllerOpenUpholdWebsite:(DWUpholdLogoutTutorialViewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:^{
        NSURL *url = [NSURL URLWithString:[DWUpholdConstants logoutURLString]];
        NSParameterAssert(url);
        [self openSafariControllerWithURL:url];
    }];
}

#pragma mark - Private

- (DWUpholdAuthViewController *)authController {
    DWUpholdAuthViewController *authController = [DWUpholdAuthViewController controller];
    authController.delegate = self;

    return authController;
}

- (DWUpholdMainViewController *)mainController {
    DWUpholdMainViewController *mainController = [DWUpholdMainViewController controller];
    mainController.delegate = self;

    return mainController;
}

- (void)upholdClientUserDidLogoutNotification:(NSNotification *)notification {
    UIViewController *toController = [self authController];
    [self dw_performTransitionToViewController:toController completion:nil];
}

- (void)openSafariControllerWithURL:(NSURL *)url {
    SFSafariViewController *controller = [SFSafariViewController dw_controllerWithURL:url];
    [self presentViewController:controller animated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END

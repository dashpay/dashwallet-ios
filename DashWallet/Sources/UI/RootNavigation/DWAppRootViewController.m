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

#import "DWAppRootViewController.h"

#import "DWHomeViewController.h"
#import "DWRootModel.h"
#import "DWSetupViewController.h"
#import "UIColor+DWStyle.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWAppRootViewController () <DWSetupViewControllerDelegate>

@property (readonly, nonatomic, strong) DWRootModel *model;
@property (nullable, nonatomic, strong) UIViewController *currentController;

@end

@implementation DWAppRootViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _model = [[DWRootModel alloc] init];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_backgroundColor];

    UIViewController *controller = nil;
    if (self.model.hasAWallet) {
        controller = [self homeController];
    }
    else {
        controller = [self setupController];
    }
    [self displayViewController:controller];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return self.currentController.preferredStatusBarStyle;
}

- (BOOL)prefersStatusBarHidden {
    return self.currentController.prefersStatusBarHidden;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (!self.model.walletOperationAllowed) {
        [self showDevicePasscodeAlert];
    }
}

#pragma mark - DWSetupViewControllerDelegate

- (void)setupViewControllerDidFinish:(DWSetupViewController *)controller {
    // TODO: transition
    UIViewController *homeController = [self homeController];
    [self displayViewController:homeController];
}

#pragma mark - Private

- (void)showDevicePasscodeAlert {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"Turn device passcode on", nil)
                         message:NSLocalizedString(@"A device passcode is needed to safeguard your wallet. Go to settings and turn passcode on to continue.", nil)
                  preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *closeButton = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"Close App", nil)
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    [[NSNotificationCenter defaultCenter] postNotificationName:DSApplicationTerminationRequestNotification object:nil];
                }];
    [alert addAction:closeButton];
    [self presentViewController:alert animated:NO completion:nil];
}

- (UIViewController *)setupController {
    UIViewController *controller = [DWSetupViewController controllerEmbededInNavigationWithDelegate:self];

    return controller;
}

- (UIViewController *)homeController {
    DWHomeViewController *controller = [DWHomeViewController controller];

    return controller;
}

- (void)displayViewController:(UIViewController *)controller {
    NSParameterAssert(controller);

    UIView *contentView = self.view;
    UIView *childView = controller.view;

    [self addChildViewController:controller];

    childView.frame = contentView.bounds;
    childView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [contentView addSubview:childView];

    [controller didMoveToParentViewController:self];

    self.currentController = controller;
}

@end

NS_ASSUME_NONNULL_END

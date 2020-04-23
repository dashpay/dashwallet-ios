//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWDashPaySetupFlowController.h"

#import "DWConfirmUsernameViewController.h"
#import "DWContainerViewController.h"
#import "DWCreateUsernameViewController.h"
#import "DWDPRegistrationStatus.h"
#import "DWRegistrationCompletedViewController.h"
#import "DWUIKit.h"
#import "DWUsernameHeaderView.h"
#import "DWUsernamePendingViewController.h"
#import "UIViewController+DWDisplayError.h"
#import "UIViewController+DWEmbedding.h"

static CGFloat const HeaderHeight(void) {
    if (IS_IPHONE_6 || IS_IPHONE_5_OR_LESS) {
        return 135.0;
    }
    else {
        return 231.0;
    }
}

static CGFloat const LandscapeHeaderHeight(void) {
    return 158.0;
}

NS_ASSUME_NONNULL_BEGIN

@interface DWDashPaySetupFlowController () <DWCreateUsernameViewControllerDelegate,
                                            DWConfirmUsernameViewControllerDelegate,
                                            DWUsernamePendingViewControllerDelegate,
                                            DWRegistrationCompletedViewControllerDelegate>

@property (readonly, nonatomic, strong) id<DWDashPayProtocol> dashPayModel;

@property (null_resettable, nonatomic, strong) DWUsernameHeaderView *headerView;
@property (null_resettable, nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) NSLayoutConstraint *headerHeightConstraint;

@property (nonatomic, strong) DWContainerViewController *containerController;
@property (null_resettable, nonatomic, strong) DWCreateUsernameViewController *createUsernameViewController;

@end

NS_ASSUME_NONNULL_END

@implementation DWDashPaySetupFlowController

- (instancetype)initWithDashPayModel:(id<DWDashPayProtocol>)dashPayModel {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _dashPayModel = dashPayModel;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.clipsToBounds = YES;
    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    [self.view addSubview:self.contentView];
    [self.view addSubview:self.headerView];

    const BOOL isLandscape = CGRectGetWidth(self.view.bounds) > CGRectGetHeight(self.view.bounds);
    const CGFloat headerHeight = isLandscape ? LandscapeHeaderHeight() : HeaderHeight();
    self.headerView.landscapeMode = isLandscape;

    [NSLayoutConstraint activateConstraints:@[
        [self.headerView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.headerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.view.trailingAnchor constraintEqualToAnchor:self.headerView.trailingAnchor],
        (self.headerHeightConstraint = [self.headerView.heightAnchor constraintEqualToConstant:headerHeight]),

        [self.contentView.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.view.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.view.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor],
    ]];

    self.containerController = [[DWContainerViewController alloc] init];
    [self dw_embedChild:self.containerController inContainer:self.contentView];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(registrationStatusUpdatedNotification)
                                                 name:DWDashPayRegistrationStatusUpdatedNotification
                                               object:nil];

    [self setCurrentStateController];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    [coordinator
        animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            BOOL isLandscape = size.width > size.height;
            self.headerView.landscapeMode = isLandscape;
            if (isLandscape) {
                self.headerHeightConstraint.constant = LandscapeHeaderHeight();
            }
            else {
                self.headerHeightConstraint.constant = HeaderHeight();
            }
        }
                        completion:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context){

                        }];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.headerView showInitialAnimation];
}

#pragma mark - Private

- (void)registrationStatusUpdatedNotification {
    if (self.dashPayModel.lastRegistrationError) {
        [self dw_displayErrorModally:self.dashPayModel.lastRegistrationError];
    }

    [self setCurrentStateController];
}

- (void)setCurrentStateController {
    if (self.dashPayModel.registrationStatus == nil || self.dashPayModel.registrationStatus.failed) {
        [self showCreateUsernameController];

        return;
    }

    if (self.dashPayModel.registrationStatus.state != DWDPRegistrationState_Done) {
        [self showPendingController:self.dashPayModel.username];
    }
    else {
        [self showRegistrationCompletedController:self.dashPayModel.username];
    }
}

- (void)createUsername:(NSString *)username {
    __weak typeof(self) weakSelf = self;
    [self.dashPayModel createUsername:username];
    [self showPendingController:username];
}

- (UIView *)contentView {
    if (_contentView == nil) {
        _contentView = [[UIView alloc] initWithFrame:CGRectZero];
        _contentView.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return _contentView;
}

- (DWUsernameHeaderView *)headerView {
    if (_headerView == nil) {
        _headerView = [[DWUsernameHeaderView alloc] initWithFrame:CGRectZero];
        _headerView.translatesAutoresizingMaskIntoConstraints = NO;
        _headerView.preservesSuperviewLayoutMargins = YES;
        [_headerView.cancelButton addTarget:self
                                     action:@selector(cancelButtonAction)
                           forControlEvents:UIControlEventTouchUpInside];
    }

    return _headerView;
}

- (DWCreateUsernameViewController *)createUsernameViewController {
    if (_createUsernameViewController == nil) {
        DWCreateUsernameViewController *controller =
            [[DWCreateUsernameViewController alloc] initWithDashPayModel:self.dashPayModel];
        controller.delegate = self;
        _createUsernameViewController = controller;
    }
    return _createUsernameViewController;
}

- (void)showPendingController:(NSString *)username {
    DWUsernamePendingViewController *controller = [[DWUsernamePendingViewController alloc] init];
    controller.username = username;
    controller.delegate = self;
    __weak DWUsernamePendingViewController *weakController = controller;
    self.headerView.titleBuilder = ^NSAttributedString *_Nonnull {
        return [weakController attributedTitle];
    };
    [self.containerController transitionToController:controller];
}

- (void)showCreateUsernameController {
    DWCreateUsernameViewController *controller = self.createUsernameViewController;
    __weak DWCreateUsernameViewController *weakController = controller;
    self.headerView.titleBuilder = ^NSAttributedString *_Nonnull {
        return [weakController attributedTitle];
    };
    [self.containerController transitionToController:controller];
}

- (void)showRegistrationCompletedController:(NSString *)username {
    NSAssert(username.length > 1, @"Invalid username");

    [self.headerView configurePlanetsViewWithUsername:username];

    DWRegistrationCompletedViewController *controller = [[DWRegistrationCompletedViewController alloc] init];
    controller.username = username;
    controller.delegate = self;
    self.headerView.titleBuilder = ^NSAttributedString *_Nonnull {
        return [[NSAttributedString alloc] init];
    };
    [self.containerController transitionToController:controller];
}

#pragma mark - Actions

- (void)cancelButtonAction {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - DWCreateUsernameViewControllerDelegate

- (void)createUsernameViewController:(DWCreateUsernameViewController *)controller
                    registerUsername:(NSString *)username {
    DWConfirmUsernameViewController *confirmController = [[DWConfirmUsernameViewController alloc] initWithUsername:username];
    confirmController.delegate = self;
    [self presentViewController:confirmController animated:YES completion:nil];
}

#pragma mark - DWConfirmUsernameViewControllerDelegate

- (void)confirmUsernameViewControllerDidConfirm:(DWConfirmUsernameViewController *)controller {
    NSString *username = controller.username;
    [controller dismissViewControllerAnimated:YES
                                   completion:^{
                                       // initiate creation process once confirmation is dismissed because
                                       // DashSync will be showing pin request modally
                                       [self createUsername:username];
                                   }];
}

#pragma mark - DWUsernamePendingViewControllerDelegate

- (void)usernamePendingViewControllerAction:(UIViewController *)controller {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - DWRegistrationCompletedViewControllerDelegate

- (void)registrationCompletedViewControllerAction:(UIViewController *)controller {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

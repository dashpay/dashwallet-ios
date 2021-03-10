//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import "DWSuccessInvitationViewController.h"

#import <LinkPresentation/LinkPresentation.h>
#import <UIViewController-KeyboardAdditions/UIViewController+KeyboardAdditions.h>

#import "DPAlertViewController+DWInvite.h"
#import "DWActionButton.h"
#import "DWEnvironment.h"
#import "DWInvitationActionsView.h"
#import "DWInvitationMessageView.h"
#import "DWInvitationPreviewViewController.h"
#import "DWScrollingViewController.h"
#import "DWSuccessInvitationTopView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSuccessInvitationViewController () <DWInvitationActionsViewDelegate>

@property (null_resettable, nonatomic, strong) DWSuccessInvitationTopView *topView;
@property (null_resettable, nonatomic, strong) DWInvitationActionsView *actionsView;
@property (null_resettable, nonatomic, strong) UIView *invitationView;
@property (null_resettable, nonatomic, strong) UIView *buttonsView;

@property (nonatomic, strong) NSLayoutConstraint *bottomConstraint;

@property (nonatomic, strong) NSURL *invitationURL;

@end

NS_ASSUME_NONNULL_END

@implementation DWSuccessInvitationViewController

- (DWSuccessInvitationTopView *)topView {
    if (_topView == nil) {
        DWSuccessInvitationTopView *topView = [[DWSuccessInvitationTopView alloc] initWithFrame:CGRectZero];
        topView.translatesAutoresizingMaskIntoConstraints = NO;
        topView.layer.cornerRadius = 8.0;
        topView.layer.masksToBounds = YES;
        [topView.previewButton addTarget:self
                                  action:@selector(previewButtonAction)
                        forControlEvents:UIControlEventTouchUpInside];
        _topView = topView;
    }
    return _topView;
}

- (DWInvitationActionsView *)actionsView {
    if (_actionsView == nil) {
        DWInvitationActionsView *actionsView = [[DWInvitationActionsView alloc] initWithFrame:CGRectZero];
        actionsView.translatesAutoresizingMaskIntoConstraints = NO;
        actionsView.delegate = self;
        _actionsView = actionsView;
    }
    return _actionsView;
}

- (UIView *)invitationView {
    if (_invitationView == nil) {
        UIView *invitationView = [[UIView alloc] init];
        invitationView.translatesAutoresizingMaskIntoConstraints = NO;

        [invitationView addSubview:self.topView];
        [invitationView addSubview:self.actionsView];

        [NSLayoutConstraint activateConstraints:@[
            [self.topView.topAnchor constraintEqualToAnchor:invitationView.topAnchor],
            [self.topView.leadingAnchor constraintEqualToAnchor:invitationView.leadingAnchor],
            [invitationView.trailingAnchor constraintEqualToAnchor:self.topView.trailingAnchor],

            [self.actionsView.topAnchor constraintEqualToAnchor:self.topView.bottomAnchor
                                                       constant:20.0],
            [self.actionsView.leadingAnchor constraintEqualToAnchor:invitationView.leadingAnchor],
            [invitationView.trailingAnchor constraintEqualToAnchor:self.actionsView.trailingAnchor],
            [invitationView.bottomAnchor constraintEqualToAnchor:self.actionsView.bottomAnchor],
        ]];

        _invitationView = invitationView;
    }
    return _invitationView;
}

- (UIView *)buttonsView {
    if (_buttonsView == nil) {
        DWActionButton *sendButton = [[DWActionButton alloc] init];
        sendButton.translatesAutoresizingMaskIntoConstraints = NO;
        [sendButton setTitle:NSLocalizedString(@"Send Invitation", nil) forState:UIControlStateNormal];
        [sendButton addTarget:self action:@selector(sendButtonAction) forControlEvents:UIControlEventTouchUpInside];

        DWActionButton *laterButton = [[DWActionButton alloc] init];
        laterButton.translatesAutoresizingMaskIntoConstraints = NO;
        laterButton.inverted = YES;
        [laterButton setTitle:NSLocalizedString(@"Maybe later", nil) forState:UIControlStateNormal];
        [laterButton addTarget:self action:@selector(laterButtonAction) forControlEvents:UIControlEventTouchUpInside];

        UIStackView *actionsView = [[UIStackView alloc] initWithArrangedSubviews:@[ sendButton, laterButton ]];
        actionsView.translatesAutoresizingMaskIntoConstraints = NO;
        actionsView.spacing = 8.0;
        actionsView.axis = UILayoutConstraintAxisVertical;

        [NSLayoutConstraint activateConstraints:@[
            [sendButton.heightAnchor constraintEqualToConstant:50],
            [laterButton.heightAnchor constraintEqualToConstant:50],
        ]];

        _buttonsView = actionsView;
    }
    return _buttonsView;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // TODO: invitation
    self.invitationURL = [NSURL URLWithString:@"https://dash.org"];

    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:contentView];

    [self.view addSubview:self.buttonsView];

    UILayoutGuide *parent = self.view.layoutMarginsGuide;
    self.bottomConstraint = [parent.bottomAnchor constraintEqualToAnchor:self.buttonsView.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [contentView.topAnchor constraintEqualToAnchor:parent.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor],
        [parent.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],

        [self.buttonsView.topAnchor constraintEqualToAnchor:contentView.bottomAnchor],
        [self.buttonsView.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor],
        [parent.trailingAnchor constraintEqualToAnchor:self.buttonsView.trailingAnchor],
        self.bottomConstraint,
    ]];

    DWScrollingViewController *scrollingController = [[DWScrollingViewController alloc] init];
    scrollingController.keyboardNotificationsEnabled = NO;
    [self dw_embedChild:scrollingController inContainer:contentView];

    [scrollingController.contentView dw_embedSubview:self.invitationView];

    // Setup model

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;
    [self.topView setBlockchainIdentity:myBlockchainIdentity];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self.topView viewWillAppear];
    [self ka_startObservingKeyboardNotifications];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.topView viewDidAppear];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];

    [self ka_stopObservingKeyboardNotifications];
}

- (void)sendButtonAction {
    NSURL *invitationURL = self.invitationURL;

    const CGSize imageSize = CGSizeMake(320, 440);
    DWInvitationMessageView *messageView = [[DWInvitationMessageView alloc] initWithFrame:CGRectMake(0, -1000, imageSize.width, imageSize.height)];
    [self.view.window addSubview:messageView];

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:imageSize];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *_Nonnull rendererContext) {
        [messageView drawViewHierarchyInRect:messageView.bounds afterScreenUpdates:YES];
    }];

    [messageView removeFromSuperview];


    UIActivityViewController *sharingController =
        [[UIActivityViewController alloc] initWithActivityItems:@[ invitationURL, image ]
                                          applicationActivities:nil];
    [self presentViewController:sharingController animated:YES completion:nil];
}

- (void)laterButtonAction {
    [self.delegate successInvitationViewControllerDidSelectLater:self];
}

- (void)previewButtonAction {
    DWInvitationPreviewViewController *previewController = [[DWInvitationPreviewViewController alloc] init];
    [self presentViewController:previewController animated:YES completion:nil];
}

- (void)ka_keyboardShowOrHideAnimationWithHeight:(CGFloat)height
                               animationDuration:(NSTimeInterval)animationDuration
                                  animationCurve:(UIViewAnimationCurve)animationCurve {
    self.bottomConstraint.constant = height;
    [self.view layoutIfNeeded];
}

#pragma mark - DWInvitationActionsViewDelegate

- (void)invitationActionsView:(DWInvitationActionsView *)view didChangeTag:(NSString *)tag {
}

- (void)invitationActionsViewCopyButtonAction:(DWInvitationActionsView *)view {
#warning "Demo"
    DPAlertViewController *alert = [DPAlertViewController insufficientFundsForInvitationAlert];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

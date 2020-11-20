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

#import "DWExternalSourceViewController.h"

#import <UIViewController-KeyboardAdditions/UIViewController+KeyboardAdditions.h>

#import "DWAvatarExternalLoadingView.h"
#import "DWAvatarExternalSourceView.h"
#import "DWModalPopupTransition.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWExternalSourceViewController () <DWAvatarExternalSourceViewDelegate, DWAvatarExternalLoadingViewDelegate>

@property (nonatomic, strong) DWModalPopupTransition *modalTransition;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) DWAvatarExternalSourceView *sourceView;
@property (nonatomic, strong) NSLayoutConstraint *centerYConstraint;
@property (nonatomic, strong) DWAvatarExternalLoadingView *loadingView;

@end

NS_ASSUME_NONNULL_END

@implementation DWExternalSourceViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _modalTransition = [[DWModalPopupTransition alloc] initWithInteractiveTransitionAllowed:NO];

        self.transitioningDelegate = self.modalTransition;
        self.modalPresentationStyle = UIModalPresentationCustom;

        self.sourceView = [[DWAvatarExternalSourceView alloc] init];
    }
    return self;
}

- (void)setCurrentInput:(NSString *)input {
    self.sourceView.input = input;
}

- (DWAvatarExternalSourceConfig *)config {
    DWAvatarExternalSourceConfig *config = [[DWAvatarExternalSourceConfig alloc] init];
    return config;
}

- (void)performLoad:(NSString *)url {
}

- (void)cancelButton {
}

- (BOOL)isInputValid:(NSString *)input {
    return YES;
}

- (void)showError:(NSString *)error {
    self.sourceView.hidden = NO;
    self.loadingView.hidden = YES;
    [self.sourceView showError:error];
}

- (void)showDefaultSubtitle {
    self.sourceView.hidden = NO;
    self.loadingView.hidden = YES;
    [self.sourceView showSubtitle];
}

- (void)showLoadingView {
    self.loadingView.hidden = NO;
    self.sourceView.hidden = YES;
}

- (void)cancelLoading {
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor clearColor];

    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.backgroundColor = [UIColor dw_backgroundColor];
    contentView.layer.cornerRadius = 8.0;
    contentView.layer.masksToBounds = YES;
    [self.view addSubview:contentView];
    self.contentView = contentView;

    self.sourceView.translatesAutoresizingMaskIntoConstraints = NO;
    self.sourceView.config = self.config;
    self.sourceView.delegate = self;
    [contentView addSubview:self.sourceView];

    DWAvatarExternalLoadingView *loadingView = [[DWAvatarExternalLoadingView alloc] init];
    loadingView.translatesAutoresizingMaskIntoConstraints = NO;
    loadingView.delegate = self;
    loadingView.hidden = YES;
    [contentView addSubview:loadingView];
    self.loadingView = loadingView;

    self.centerYConstraint = [contentView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.centerYConstraint,

        [self.sourceView.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                  constant:32.0],
        [self.sourceView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.sourceView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:self.sourceView.bottomAnchor
                                                 constant:32.0],

        [loadingView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [loadingView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [loadingView.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // pre-layout view to avoid undesired animation if the keyboard is shown while appearing
    [self.view layoutIfNeeded];
    [self ka_startObservingKeyboardNotifications];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self ka_stopObservingKeyboardNotifications];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.sourceView activateTextField];
}

#pragma mark - Keyboard

- (void)ka_keyboardShowOrHideAnimationWithHeight:(CGFloat)height
                               animationDuration:(NSTimeInterval)animationDuration
                                  animationCurve:(UIViewAnimationCurve)animationCurve {
    if (height == 0) {
        self.centerYConstraint.constant = 0;
    }
    else {
        self.centerYConstraint.constant = -(CGRectGetHeight(self.view.bounds) - CGRectGetHeight(self.contentView.bounds)) / 2.0;
    }
    [self.view layoutIfNeeded];
}

#pragma mark - DWAvatarExternalSourceViewDelegate

- (void)avatarExternalSourceViewOKAction:(DWAvatarExternalSourceView *)view {
    if ([self isInputValid:view.input]) {
        [self.view endEditing:YES];
        [self performLoad:view.input];
    }
}

- (void)avatarExternalSourceViewCancelAction:(DWAvatarExternalSourceView *)view {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - DWAvatarExternalLoadingViewDelegate

- (void)avatarExternalLoadingViewCancelAction:(DWAvatarExternalLoadingView *)view {
    [self cancelLoading];
}

@end

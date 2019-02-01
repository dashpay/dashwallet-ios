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

#import "DWAlertController.h"

#import "DWAlertAction+DWProtected.h"
#import "DWAlertDismissalAnimationController.h"
#import "DWAlertInternalConstants.h"
#import "DWAlertPresentationAnimationController.h"
#import "DWAlertPresentationController.h"
#import "DWAlertView.h"
#import "UIViewController+KeyboardAdditions.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const HorizontalPadding = 16.0;
static CGFloat const VerticalPadding = 20.0;

@interface DWAlertController () <UIViewControllerTransitioningDelegate, DWAlertViewDelegate>

@property (null_resettable, strong, nonatomic) DWAlertView *alertView;
@property (strong, nonatomic) NSLayoutConstraint *alertViewCenterYConstraint;

@property (nullable, strong, nonatomic) UIViewController *contentController;
@property (copy, nonatomic) NSArray<DWAlertAction *> *actions;

@end

@implementation DWAlertController

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [self setupAlertController];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self setupAlertController];
    }
    return self;
}

- (void)setupAlertController {
    self.modalPresentationStyle = UIModalPresentationCustom;
    self.transitioningDelegate = self;
    self.actions = @[];
}

- (DWAlertView *)alertView {
    if (!_alertView) {
        DWAlertView *alertView = [[DWAlertView alloc] initWithFrame:self.view.bounds];
        alertView.translatesAutoresizingMaskIntoConstraints = NO;
        alertView.delegate = self;
        [self.view addSubview:alertView];
        CGFloat maxAlertViewHeight = CGRectGetHeight([UIScreen mainScreen].bounds);
        maxAlertViewHeight -= VerticalPadding * 2.0; // padding from top and bottom of the screen
        [NSLayoutConstraint activateConstraints:@[
            [alertView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            (self.alertViewCenterYConstraint = [alertView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]),
            [alertView.widthAnchor constraintEqualToConstant:DWAlertViewWidth],
            [alertView.heightAnchor constraintLessThanOrEqualToConstant:maxAlertViewHeight],
        ]];
        _alertView = alertView;
    }
    return _alertView;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    NSAssert(self.contentController, @"Alert must be configured with a content controller");

    [self ka_startObservingKeyboardNotifications];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self ka_stopObservingKeyboardNotifications];

    [self.view endEditing:YES];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    [self updateDimmedViewVisiblePath];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    [self.alertView resetActionsState];
}

#pragma mark - Public

- (void)setupContentController:(UIViewController *)controller {
    NSParameterAssert(controller);
    NSAssert(!self.contentController, @"Content view controller already set");

    self.contentController = controller;
    [self displayViewController:controller];
}

- (void)performTransitionToContentController:(UIViewController *)controller {
    NSParameterAssert(controller);
    NSAssert(self.contentController, @"Content view controller should exist");

    [self performTransitionFromViewController:self.contentController toViewController:controller];
    self.contentController = controller;
}

- (void)addAction:(DWAlertAction *)action {
    NSParameterAssert(action);

    NSMutableArray *mutableActions = [self.actions mutableCopy];
    [mutableActions addObject:action];
    self.actions = mutableActions;

    [self.alertView addAction:action];

    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

- (void)setupActions:(NSArray<DWAlertAction *> *)actions {
    NSParameterAssert(actions);

    [self.alertView removeAllActions];

    self.actions = actions;

    for (DWAlertAction *action in actions) {
        [self.alertView addAction:action];
    }

    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

- (nullable DWAlertAction *)preferredAction {
    return self.alertView.preferredAction;
}

- (void)setPreferredAction:(nullable DWAlertAction *)preferredAction {
    NSAssert([self.actions indexOfObject:preferredAction] != NSNotFound, @"The action object you assign to this property must have already been added to the alert controller’s list of actions.");
    self.alertView.preferredAction = preferredAction;
}

#pragma mark - DWAlertViewDelegate

- (void)alertView:(DWAlertView *)alertView didAction:(DWAlertAction *)action {
    if (action.handler) {
        action.handler(action);
    }
    else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - UIViewControllerTransitioningDelegate

- (nullable id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
                                                                           presentingController:(UIViewController *)presenting
                                                                               sourceController:(UIViewController *)source {
    DWAlertPresentationAnimationController *animationController = [[DWAlertPresentationAnimationController alloc] init];
    return animationController;
}

- (nullable id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    DWAlertDismissalAnimationController *animationController = [[DWAlertDismissalAnimationController alloc] init];
    return animationController;
}

- (nullable UIPresentationController *)presentationControllerForPresentedViewController:(UIViewController *)presented
                                                               presentingViewController:(nullable UIViewController *)presenting
                                                                   sourceViewController:(UIViewController *)source {
    DWAlertPresentationController *presentationController = [[DWAlertPresentationController alloc] initWithPresentedViewController:presented presentingViewController:presenting];
    return presentationController;
}

#pragma mark - Keyboard

- (void)ka_keyboardWillShowOrHideWithHeight:(CGFloat)height
                          animationDuration:(NSTimeInterval)animationDuration
                             animationCurve:(UIViewAnimationCurve)animationCurve {
    [self keyboardWillShowOrHideWithHeight:height];
}

- (void)ka_keyboardShowOrHideAnimationWithHeight:(CGFloat)height
                               animationDuration:(NSTimeInterval)animationDuration
                                  animationCurve:(UIViewAnimationCurve)animationCurve {
    [self keyboardShowOrHideAnimation];
}

#pragma mark - Private

- (void)keyboardWillShowOrHideWithHeight:(CGFloat)height {
    UIView *alertView = self.alertView;
    NSLayoutConstraint *alertViewCenterYConstraint = self.alertViewCenterYConstraint;
    if (!alertView || !alertViewCenterYConstraint) {
        return;
    }

    [self.class updateContraintForKeyboardHeight:height
                                      parentView:self.view
                                alertContentView:alertView
               alertContentViewCenterYConstraint:alertViewCenterYConstraint];
}

- (void)keyboardShowOrHideAnimation {
    UIView *alertView = self.alertView;
    NSLayoutConstraint *alertViewCenterYConstraint = self.alertViewCenterYConstraint;
    if (!alertView || !alertViewCenterYConstraint) {
        return;
    }

    [self updateDimmedViewVisiblePath];

    [self.view layoutIfNeeded];
}

+ (void)updateContraintForKeyboardHeight:(CGFloat)height
                              parentView:(UIView *)parentView
                        alertContentView:(UIView *)alertContentView
       alertContentViewCenterYConstraint:(NSLayoutConstraint *)alertContentViewCenterYConstraint {
    if (height > 0.0) {
        CGFloat viewHeight = CGRectGetHeight(parentView.bounds);
        CGFloat alertHeight = CGRectGetHeight(alertContentView.frame);
        CGFloat contentBottom = (viewHeight - alertHeight) / 2.0 + alertHeight;
        CGFloat keyboardTop = viewHeight - height;
        CGFloat space = keyboardTop - contentBottom;
        if (space >= VerticalPadding) {
            alertContentViewCenterYConstraint.constant = 0.0;
        }
        else {
            CGFloat constant = VerticalPadding + ABS(space);
            alertContentViewCenterYConstraint.constant = -constant;
        }
    }
    else {
        alertContentViewCenterYConstraint.constant = 0.0;
    }
}

- (void)updateDimmedViewVisiblePath {
    DWAlertPresentationController *presentationController = (DWAlertPresentationController *)self.presentationController;
    if ([presentationController isKindOfClass:DWAlertPresentationController.class]) {
        CGFloat viewHeight = CGRectGetHeight(self.view.bounds);
        CGFloat alertHeight = CGRectGetHeight(self.alertView.frame);
        CGFloat centeredAlertY = (viewHeight - alertHeight) / 2.0;
        CGFloat alertY = centeredAlertY + self.alertViewCenterYConstraint.constant;

        CGRect rect = CGRectMake(CGRectGetMinX(self.alertView.frame),
                                 alertY,
                                 CGRectGetWidth(self.alertView.frame),
                                 alertHeight);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:DWAlertViewCornerRadius];
        presentationController.dimmingView.visiblePath = path;
    }
}

- (void)displayViewController:(UIViewController *)controller {
    NSParameterAssert(controller);

    UIView *contentView = self.alertView.contentView;
    UIView *childView = controller.view;

    [self addChildViewController:controller];
    [contentView addSubview:childView];

    childView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [childView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:VerticalPadding],
        [childView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:HorizontalPadding],
        [childView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-VerticalPadding],
        [childView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-HorizontalPadding],
    ]];

    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];

    [controller didMoveToParentViewController:self];
}

- (void)performTransitionFromViewController:(UIViewController *)fromViewController
                           toViewController:(UIViewController *)toViewController {
    UIView *toView = toViewController.view;
    UIView *fromView = fromViewController.view;
    UIView *contentView = self.alertView.contentView;

    [fromViewController willMoveToParentViewController:nil];

    [self addChildViewController:toViewController];
    [contentView addSubview:toView];

    toView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [toView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:VerticalPadding],
        [toView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:HorizontalPadding],
        [toView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-VerticalPadding],
        [toView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-HorizontalPadding],
    ]];

    toView.alpha = 0.0;

    [UIView animateWithDuration:0.3
        delay:0.0
        usingSpringWithDamping:1.0
        initialSpringVelocity:0.0
        options:UIViewAnimationOptionCurveEaseInOut
        animations:^{
            toView.alpha = 1.0;
            fromView.alpha = 0.0;
        }
        completion:^(BOOL finished) {
            [fromView removeFromSuperview];
            [fromViewController removeFromParentViewController];
            [toViewController didMoveToParentViewController:self];
        }];
}

@end

NS_ASSUME_NONNULL_END

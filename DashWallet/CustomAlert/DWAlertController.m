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
#import "DWAlertController+DWKeyboard.h"
#import "DWAlertDismissalAnimationController.h"
#import "DWAlertInternalConstants.h"
#import "DWAlertPresentationAnimationController.h"
#import "DWAlertPresentationController.h"
#import "DWAlertView.h"
#import "DWAlertViewActionBaseView.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWAlertController () <UIViewControllerTransitioningDelegate, DWAlertViewDelegate>

@property (null_resettable, strong, nonatomic) DWAlertView *alertView;
@property (strong, nonatomic) NSLayoutConstraint *alertViewCenterYConstraint;
@property (strong, nonatomic) NSLayoutConstraint *alertViewHeightConstraint;

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

        CGFloat maximumAllowedViewHeight = [self maximumAllowedAlertHeightWithKeyboard:0.0];
        [NSLayoutConstraint activateConstraints:@[
            [alertView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            (self.alertViewCenterYConstraint = [alertView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]),
            [alertView.widthAnchor constraintEqualToConstant:DWAlertViewWidth],
            (self.alertViewHeightConstraint = [alertView.heightAnchor constraintLessThanOrEqualToConstant:maximumAllowedViewHeight]),
        ]];
        _alertView = alertView;
    }
    return _alertView;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    NSAssert(self.contentController, @"Alert must be configured with a content controller");

    [self dw_startObservingKeyboardNotifications];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self dw_stopObservingKeyboardNotifications];
    [self.view endEditing:YES];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    [self updateDimmedViewVisiblePath];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        CGFloat maximumAllowedViewHeight = [self maximumAllowedAlertHeightWithKeyboard:self.dw_keyboardHeight];

        self.alertViewHeightConstraint.constant = maximumAllowedViewHeight;
        [self.alertView setNeedsLayout];
        [self.alertView layoutIfNeeded];
        [self.alertView resetActionsState];
    }
                                 completion:nil];
}

#pragma mark - Public

- (Class)actionViewClass {
    return self.alertView.actionViewClass;
}

- (void)setActionViewClass:(nullable Class)actionViewClass {
    NSAssert([actionViewClass isSubclassOfClass:DWAlertViewActionBaseView.class], @"actionViewClass must be a subclass of DWAlertViewActionBaseView");
    NSAssert(self.actions.count == 0, @"actionViewClass should be set before adding any actions");
    self.alertView.actionViewClass = actionViewClass;
}

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

#ifdef DEBUG
    if (action.style == DWAlertActionStyleCancel) {
        for (DWAlertAction *a in self.actions) {
            if (a.style == DWAlertActionStyleCancel) {
                NSAssert(NO, @"DWAlertController can only have one action with a style of DWAlertActionStyleCancel");
            }
        }
    }
#endif

    NSMutableArray *mutableActions = [self.actions mutableCopy];
    [mutableActions addObject:action];
    self.actions = mutableActions;

    [self.alertView addAction:action];

    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

- (void)setupActions:(NSArray<DWAlertAction *> *)actions {
    NSParameterAssert(actions);

#ifdef DEBUG
    BOOL hasCancelAction = NO;
    for (DWAlertAction *a in actions) {
        if (hasCancelAction && a.style == DWAlertActionStyleCancel) {
            NSAssert(NO, @"DWAlertController can only have one action with a style of DWAlertActionStyleCancel");
        }
        hasCancelAction = a.style == DWAlertActionStyleCancel;
    }
#endif

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

- (void)dw_keyboardWillShowOrHideWithHeight:(CGFloat)height
                          animationDuration:(NSTimeInterval)animationDuration
                             animationCurve:(UIViewAnimationCurve)animationCurve {
    CGFloat maximumAllowedViewHeight = [self maximumAllowedAlertHeightWithKeyboard:height];
    self.alertViewHeightConstraint.constant = maximumAllowedViewHeight;
    self.alertViewCenterYConstraint.constant = -height / 2.0;
}

- (void)dw_keyboardShowOrHideAnimationWithHeight:(CGFloat)height
                               animationDuration:(NSTimeInterval)animationDuration
                                  animationCurve:(UIViewAnimationCurve)animationCurve {
    [self.alertView setNeedsLayout];
    [self.alertView layoutIfNeeded];
    [self.view layoutIfNeeded];
}

#pragma mark - Private

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
    CGFloat verticalPadding = DWAlertViewContentVerticalPadding;
    CGFloat horizontalPadding = DWAlertViewContentHorizontalPadding;
    [NSLayoutConstraint activateConstraints:@[
        [childView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:verticalPadding],
        [childView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:horizontalPadding],
        [childView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-verticalPadding],
        [childView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-horizontalPadding],
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
    CGFloat verticalPadding = DWAlertViewContentVerticalPadding;
    CGFloat horizontalPadding = DWAlertViewContentHorizontalPadding;
    [NSLayoutConstraint activateConstraints:@[
        [toView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:verticalPadding],
        [toView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:horizontalPadding],
        [toView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-verticalPadding],
        [toView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-horizontalPadding],
    ]];

    toView.alpha = 0.0;

    [UIView animateWithDuration:DWAlertInplaceTransitionAnimationDuration
        delay:0.0
        usingSpringWithDamping:DWAlertInplaceTransitionAnimationDampingRatio
        initialSpringVelocity:DWAlertInplaceTransitionAnimationInitialVelocity
        options:DWAlertInplaceTransitionAnimationOptions
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

- (CGFloat)maximumAllowedAlertHeightWithKeyboard:(CGFloat)keyboardHeight {
    CGFloat minInset;
    if (@available(iOS 11.0, *)) {
        UIEdgeInsets insets = [UIApplication sharedApplication].delegate.window.safeAreaInsets;
        minInset = MAX(insets.top, insets.bottom);
    }
    else {
        minInset = MAX(self.topLayoutGuide.length, self.bottomLayoutGuide.length);
    }

    CGFloat padding = DWAlertViewVerticalPadding(minInset, keyboardHeight > 0.0);
    CGFloat height = CGRectGetHeight([UIScreen mainScreen].bounds) - padding * 2.0 - keyboardHeight;

    return height;
}

@end

NS_ASSUME_NONNULL_END

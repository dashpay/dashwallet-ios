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

#import "DWAlertViewController.h"

#import "DWAlertDismissalAnimationController.h"
#import "DWAlertPresentationAnimationController.h"
#import "DWAlertPresentationController.h"
#import <UIViewController+KeyboardAdditions.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DWAlertViewController

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
    self.shouldDimBackground = YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self ka_startObservingKeyboardNotifications];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self ka_stopObservingKeyboardNotifications];
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
    presentationController.shouldDimBackground = self.shouldDimBackground;
    return presentationController;
}

#pragma mark - DWAlertKeyboardSupport

- (nullable UIView *)alertContentView {
    return nil;
}

- (nullable NSLayoutConstraint *)alertContentViewCenterYConstraint {
    return nil;
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

#pragma mark - Internal

- (void)keyboardWillShowOrHideWithHeight:(CGFloat)height {
    UIView *alertContentView = self.alertContentView;
    NSLayoutConstraint *alertContentViewCenterYConstraint = self.alertContentViewCenterYConstraint;
    if (!alertContentView || !alertContentViewCenterYConstraint) {
        return;
    }

    [self.class updateContraintForKeyboardHeight:height
                                      parentView:self.view
                                alertContentView:alertContentView
               alertContentViewCenterYConstraint:alertContentViewCenterYConstraint];
}

- (void)keyboardShowOrHideAnimation {
    UIView *alertContentView = self.alertContentView;
    NSLayoutConstraint *alertContentViewCenterYConstraint = self.alertContentViewCenterYConstraint;
    if (!alertContentView || !alertContentViewCenterYConstraint) {
        return;
    }

    [self.view layoutIfNeeded];
}

+ (void)updateContraintForKeyboardHeight:(CGFloat)height
                              parentView:(UIView *)parentView
                        alertContentView:(UIView *)alertContentView
       alertContentViewCenterYConstraint:(NSLayoutConstraint *)alertContentViewCenterYConstraint {
    if (height > 0.0) {
        CGFloat viewHeight = CGRectGetHeight(parentView.bounds);
        CGFloat contentBottom = CGRectGetMinY(alertContentView.frame) + CGRectGetHeight(alertContentView.bounds);
        CGFloat keyboardTop = viewHeight - height;
        CGFloat space = keyboardTop - contentBottom;
        CGFloat const padding = 16.0;
        if (space >= padding) {
            alertContentViewCenterYConstraint.constant = 0.0;
        }
        else {
            alertContentViewCenterYConstraint.constant = -(padding - space);
        }
    }
    else {
        alertContentViewCenterYConstraint.constant = 0.0;
    }
}

@end

NS_ASSUME_NONNULL_END

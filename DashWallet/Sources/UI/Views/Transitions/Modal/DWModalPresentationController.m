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

#import "DWModalPresentationController.h"

#import "DWModalInteractiveTransition.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

CGFloat DWModalPresentedHeightPercent(void) {
    if (IS_IPHONE_5_OR_LESS) {
        return 6.0 / 7.0;
    }
    else if (IS_IPHONE_6) {
        return 3.0 / 4.0;
    }
    else {
        return 2.0 / 3.0;
    }
}

@interface DWModalPresentationController ()

@property (null_resettable, nonatomic, strong) UIView *dimmingView;
@property (null_resettable, nonatomic, strong) UIView *bottomView;

@end

@implementation DWModalPresentationController

- (BOOL)shouldPresentInFullscreen {
    return NO;
}

- (CGRect)frameOfPresentedViewInContainerView {
    const CGRect bounds = self.containerView.bounds;
    const CGFloat height = CGRectGetHeight(bounds);
    const CGFloat width = CGRectGetWidth(bounds);

    if (self.controllerDelegate && [self.controllerDelegate respondsToSelector:@selector(contentViewHeight)]) {
        CGFloat contentViewHeight = [self.controllerDelegate contentViewHeight];

        return CGRectMake(0.0, height - contentViewHeight, width, contentViewHeight);
    }

    const CGFloat viewHeight = ceil(height * DWModalPresentedHeightPercent());
    const CGRect frame = CGRectMake(0.0, height - viewHeight, width, viewHeight);

    return frame;
}

- (void)containerViewDidLayoutSubviews {
    [super containerViewDidLayoutSubviews];

    self.dimmingView.frame = self.containerView.bounds;
    self.presentedView.frame = self.frameOfPresentedViewInContainerView;
}

- (void)presentationTransitionWillBegin {
    [super presentationTransitionWillBegin];

    UIView *presentedView = self.presentedView;
    NSParameterAssert(presentedView);
    [self.containerView addSubview:presentedView];

    if (IS_IPHONE) {
        UIView *bottomView = self.bottomView;
        [presentedView addSubview:bottomView];

        CGFloat height = CGRectGetMaxY(presentedView.frame);

        [NSLayoutConstraint activateConstraints:@[
            [bottomView.topAnchor constraintEqualToAnchor:presentedView.bottomAnchor],
            [bottomView.heightAnchor constraintEqualToConstant:height],
            [bottomView.widthAnchor constraintEqualToAnchor:presentedView.widthAnchor],
        ]];
    }

    [self.containerView insertSubview:self.dimmingView atIndex:0];
    [self performBlockAnimatedIfPossible:^{
        self.dimmingView.alpha = 1.0;
    }];
}

- (void)presentationTransitionDidEnd:(BOOL)completed {
    [super presentationTransitionDidEnd:completed];

    NSParameterAssert(self.interactiveTransition);
    if (completed) {
        self.interactiveTransition.presenting = NO;
    }

    if (!completed) {
        [self.dimmingView removeFromSuperview];
    }
}

- (void)dismissalTransitionWillBegin {
    [super dismissalTransitionWillBegin];

    [self performBlockAnimatedIfPossible:^{
        self.dimmingView.alpha = 0.0;
    }];
}

- (void)dismissalTransitionDidEnd:(BOOL)completed {
    [super dismissalTransitionDidEnd:completed];

    if (completed) {
        [self.dimmingView removeFromSuperview];
    }
}

#pragma mark - Private

- (UIView *)dimmingView {
    if (!_dimmingView) {
        UIView *dimmingView = [[UIView alloc] initWithFrame:self.containerView.bounds];
        dimmingView.backgroundColor = [UIColor dw_modalDimmingColor];
        dimmingView.alpha = 0.0;

        UITapGestureRecognizer *tapGestureRecognizer =
            [[UITapGestureRecognizer alloc] initWithTarget:self
                                                    action:@selector(tapGestureRecognizerAction:)];
        [dimmingView addGestureRecognizer:tapGestureRecognizer];

#if SNAPSHOT
        dimmingView.accessibilityIdentifier = @"modal_dimming_view";
#endif /* SNAPSHOT */

        _dimmingView = dimmingView;
    }
    return _dimmingView;
}

- (UIView *)bottomView {
    if (!_bottomView) {
        UIView *presentedView = self.presentedView;

        CGRect frame = presentedView.frame;

        UIView *bottomView = [[UIView alloc] initWithFrame:frame];
        bottomView.translatesAutoresizingMaskIntoConstraints = NO;
        bottomView.backgroundColor = presentedView.backgroundColor;

#if SNAPSHOT
        bottomView.accessibilityIdentifier = @"modal_bottom_view";
#endif /* SNAPSHOT */

        _bottomView = bottomView;
    }

    return _bottomView;
}

- (void)tapGestureRecognizerAction:(id)sender {
    if (self.interactiveTransition.interactiveTransitionAllowed) {
        if ([self.interactiveTransition.presentedController respondsToSelector:@selector(interactiveTransitionWillDismiss)])
            [self.interactiveTransition.presentedController interactiveTransitionWillDismiss];

        [self.interactiveTransition.presentedController dismissViewControllerAnimated:YES
                                                                           completion:nil];
    }
}

- (void)performBlockAnimatedIfPossible:(void (^)(void))block {
    id<UIViewControllerTransitionCoordinator> coordinator = self.presentedViewController.transitionCoordinator;
    if (coordinator) {
        [coordinator
            animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context) {
                block();
            }
                            completion:nil];
    }
    else {
        block();
    }
}

@end

NS_ASSUME_NONNULL_END

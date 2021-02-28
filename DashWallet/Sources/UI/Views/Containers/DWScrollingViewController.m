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

#import "DWScrollingViewController.h"

#import <UIViewController-KeyboardAdditions/UIViewController+KeyboardAdditions.h>

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWScrollingViewController ()

@property (null_resettable, nonatomic, strong) UIScrollView *scrollView;
@property (null_resettable, nonatomic, strong) UIView *contentView;
@property (null_resettable, nonatomic, strong) NSLayoutConstraint *bottomConstraint;

@end

NS_ASSUME_NONNULL_END

@implementation DWScrollingViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.keyboardNotificationsEnabled = YES;
    }
    return self;
}

- (UIScrollView *)scrollView {
    if (_scrollView == nil) {
        _scrollView = [[UIScrollView alloc] init];
        _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
        _scrollView.alwaysBounceVertical = YES;
        _scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
        _scrollView.preservesSuperviewLayoutMargins = YES;
    }
    return _scrollView;
}

- (UIView *)contentView {
    if (_contentView == nil) {
        _contentView = [[UIView alloc] init];
        _contentView.translatesAutoresizingMaskIntoConstraints = NO;
        _contentView.preservesSuperviewLayoutMargins = YES;
    }
    return _contentView;
}

- (NSLayoutConstraint *)bottomConstraint {
    if (_bottomConstraint == nil) {
        _bottomConstraint = [self.view.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor];
    }
    return _bottomConstraint;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self.view addSubview:self.scrollView];
    [self.scrollView addSubview:self.contentView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.view.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        self.bottomConstraint,

        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (self.keyboardNotificationsEnabled) {
        [self ka_startObservingKeyboardNotifications];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];

    if (self.keyboardNotificationsEnabled) {
        [self ka_stopObservingKeyboardNotifications];
    }
}

- (UIViewController *)childViewControllerForStatusBarStyle {
    return self.childViewControllers.firstObject;
}

- (void)ka_keyboardShowOrHideAnimationWithHeight:(CGFloat)height
                               animationDuration:(NSTimeInterval)animationDuration
                                  animationCurve:(UIViewAnimationCurve)animationCurve {
    self.bottomConstraint.constant = height;
    [self.view layoutIfNeeded];
}

@end

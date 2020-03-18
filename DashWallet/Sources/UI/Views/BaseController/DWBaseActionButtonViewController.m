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

#import "DWBaseActionButtonViewController.h"

#import <UIViewController-KeyboardAdditions/UIViewController+KeyboardAdditions.h>

#import "DWBlueActionButton.h"
#import "DWUIKit.h"
#import "DevicesCompatibility.h"

NS_ASSUME_NONNULL_BEGIN

static UIEdgeInsets const SCROLL_INDICATOR_INSETS = {0.0, 0.0, 0.0, -3.0};
static CGFloat const SPACING = 16.0;

CGFloat DWBottomButtonHeight(void) {
    if (IS_IPHONE_5_OR_LESS || IS_IPHONE_6) {
        return 44.0;
    }
    else {
        return 54.0;
    }
}

#pragma mark - Helper

@interface UIButton (DWActionButtonProtocol_UIButton) <DWActionButtonProtocol>
@end
@implementation UIButton (DWActionButtonProtocol_UIButton)
@end

@interface UIBarButtonItem (DWActionButtonProtocol_UIBarButtonItem) <DWActionButtonProtocol>
@end
@implementation UIBarButtonItem (DWActionButtonProtocol_UIBarButtonItem)
@end

#pragma mark - Controller

@interface DWBaseActionButtonViewController ()

@property (nullable, nonatomic, strong) UIStackView *stackView;
@property (nullable, nonatomic, strong) id<DWActionButtonProtocol> actionButton;

@property (nullable, nonatomic, strong) UIButton *bottomActionButton;
@property (nullable, nonatomic, strong) UIBarButtonItem *barActionButton;
@property (nullable, nonatomic, strong) UIActivityIndicatorView *activityIndicatorView;

@property (nullable, strong, nonatomic) NSLayoutConstraint *contentBottomConstraint;

@end

@implementation DWBaseActionButtonViewController

+ (BOOL)showsActionButton {
    return YES;
}

+ (BOOL)isActionButtonInNavigationBar {
    return IS_IPHONE_5_OR_LESS;
}

- (NSString *)actionButtonTitle {
    NSAssert(NO, @"Must be overriden in subclass");
    return nil;
}

- (NSString *)actionButtonDisabledTitle {
    return [self actionButtonTitle];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self baseActionButtonView_setup];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (self.isKeyboardNotificationsEnabled) {
        // pre-layout view to avoid undesired animation if the keyboard is shown while appearing
        [self.view layoutIfNeeded];
        [self ka_startObservingKeyboardNotifications];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    if (self.isKeyboardNotificationsEnabled) {
        [self ka_stopObservingKeyboardNotifications];
    }
}

- (void)setupContentView:(UIView *)contentView {
    NSParameterAssert(self.stackView);
    NSParameterAssert(contentView);

    [self.stackView insertArrangedSubview:contentView atIndex:0];
}

- (void)reloadActionButtonTitles {
    NSString *actionButtonTitle = [self actionButtonTitle];
    NSString *actionButtonDisabledTitle = [self actionButtonDisabledTitle];
    if (![self.class isActionButtonInNavigationBar]) {
        [(DWBlueActionButton *)self.actionButton setTitle:actionButtonTitle forState:UIControlStateNormal];
        [(DWBlueActionButton *)self.actionButton setTitle:actionButtonDisabledTitle forState:UIControlStateDisabled];
    }
}

- (void)showActivityIndicator {
    if ([self.class isActionButtonInNavigationBar]) {
        UIActivityIndicatorView *activityIndicator = [self configuredActivityIndicator];
        [activityIndicator startAnimating];
        [activityIndicator sizeToFit];
        UIBarButtonItem *barButtonItem = [[UIBarButtonItem alloc] initWithCustomView:activityIndicator];
        self.navigationItem.rightBarButtonItem = barButtonItem;
    }
    else {
        NSParameterAssert(self.activityIndicatorView);
        NSParameterAssert(self.bottomActionButton);
        self.bottomActionButton.hidden = YES;
        self.activityIndicatorView.hidden = NO;
        [self.activityIndicatorView startAnimating];
    }
}

- (void)hideActivityIndicator {
    if ([self.class isActionButtonInNavigationBar]) {
        self.navigationItem.rightBarButtonItem = self.barActionButton;
    }
    else {
        self.activityIndicatorView.hidden = YES;
        self.bottomActionButton.hidden = NO;
    }
}

#pragma mark - Actions

- (void)actionButtonAction:(id)sender {
    // NOP
}

#pragma mark - Keyboard

- (void)ka_keyboardShowOrHideAnimationWithHeight:(CGFloat)height
                               animationDuration:(NSTimeInterval)animationDuration
                                  animationCurve:(UIViewAnimationCurve)animationCurve {
    const CGFloat bottomPadding = [self.class deviceSpecificBottomPadding];
    self.contentBottomConstraint.constant = height + bottomPadding;
    [self.view layoutIfNeeded];
}

#pragma mark - Private

- (void)baseActionButtonView_setup {
    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    NSMutableArray<__kindof UIView *> *arrangedSubviews = [NSMutableArray array];

    DWBlueActionButton *bottomActionButton = nil;
    if ([self.class showsActionButton]) {
        NSString *actionButtonTitle = [self actionButtonTitle];
        NSString *actionButtonDisabledTitle = [self actionButtonDisabledTitle];
        NSParameterAssert(actionButtonTitle);

        if ([self.class isActionButtonInNavigationBar]) {
            UIBarButtonItem *barButtonItem = [[UIBarButtonItem alloc]
                initWithTitle:actionButtonTitle
                        style:UIBarButtonItemStylePlain
                       target:self
                       action:@selector(actionButtonAction:)];
            self.navigationItem.rightBarButtonItem = barButtonItem;
            self.actionButton = barButtonItem;
            self.barActionButton = barButtonItem;
        }
        else {
            bottomActionButton = [[DWBlueActionButton alloc] initWithFrame:CGRectZero];
            bottomActionButton.translatesAutoresizingMaskIntoConstraints = NO;
            [bottomActionButton setTitle:actionButtonTitle forState:UIControlStateNormal];
            [bottomActionButton setTitle:actionButtonDisabledTitle forState:UIControlStateDisabled];
            [bottomActionButton addTarget:self
                                   action:@selector(actionButtonAction:)
                         forControlEvents:UIControlEventTouchUpInside];
            self.actionButton = bottomActionButton;
            [arrangedSubviews addObject:bottomActionButton];
            self.bottomActionButton = bottomActionButton;

            UIActivityIndicatorView *activityIndicatorView = [self configuredActivityIndicator];
            activityIndicatorView.translatesAutoresizingMaskIntoConstraints = NO;
            activityIndicatorView.hidden = YES;
            [arrangedSubviews addObject:activityIndicatorView];
            self.activityIndicatorView = activityIndicatorView;
        }

        self.actionButton.enabled = NO;
    }

    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:arrangedSubviews];
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.alignment = UIStackViewAlignmentFill;
    stackView.distribution = UIStackViewDistributionFill;
    stackView.spacing = SPACING;
    [self.view addSubview:stackView];
    self.stackView = stackView;

    UILayoutGuide *marginsGuide = self.view.layoutMarginsGuide;
    UILayoutGuide *safeAreaGuide = self.view.safeAreaLayoutGuide;

    const CGFloat bottomPadding = [self.class deviceSpecificBottomPadding];
    // constraint relation is inverted so we can use positive padding values
    self.contentBottomConstraint = [safeAreaGuide.bottomAnchor constraintEqualToAnchor:stackView.bottomAnchor
                                                                              constant:bottomPadding];

    [NSLayoutConstraint activateConstraints:@[
        [stackView.topAnchor constraintEqualToAnchor:safeAreaGuide.topAnchor],
        [stackView.leadingAnchor constraintEqualToAnchor:marginsGuide.leadingAnchor],
        [stackView.trailingAnchor constraintEqualToAnchor:marginsGuide.trailingAnchor],
        self.contentBottomConstraint,
    ]];

    if (bottomActionButton) {
        [bottomActionButton.heightAnchor constraintEqualToConstant:DWBottomButtonHeight()].active = YES;
    }
}

- (UIActivityIndicatorView *)configuredActivityIndicator {
    UIActivityIndicatorView *activityIndicatorView = nil;

    if ([self.class isActionButtonInNavigationBar]) {
        activityIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        activityIndicatorView.color = [UIColor dw_tintColor];
    }
    else {
        activityIndicatorView =
            [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        activityIndicatorView.color = [UIColor dw_iconTintColor];
    }

    return activityIndicatorView;
}

#pragma mark - Configuration

+ (CGFloat)deviceSpecificBottomPadding {
    if ([self isActionButtonInNavigationBar]) {
        return 0.0;
    }
    else {
        return [super deviceSpecificBottomPadding];
    }
}

@end

NS_ASSUME_NONNULL_END

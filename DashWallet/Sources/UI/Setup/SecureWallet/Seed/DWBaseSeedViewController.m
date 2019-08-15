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

#import "DWBaseSeedViewController.h"

#import "DWBlueActionButton.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static UIEdgeInsets const SCROLL_INDICATOR_INSETS = {0.0, 0.0, 0.0, -3.0};

#pragma mark - Helper

@interface UIButton (DWSeedContinueButton_UIButton) <DWSeedContinueButton>
@end
@implementation UIButton (DWSeedContinueButton_UIButton)
@end

@interface UIBarButtonItem (DWSeedContinueButton_UIBarButtonItem) <DWSeedContinueButton>
@end
@implementation UIBarButtonItem (DWSeedContinueButton_UIBarButtonItem)
@end

#pragma mark - Controller

@interface DWBaseSeedViewController ()

@property (nullable, nonatomic, strong) UIScrollView *scrollView;
@property (nullable, nonatomic, strong) id<DWSeedContinueButton> continueButton;

@property (nullable, strong, nonatomic) NSLayoutConstraint *contentBottomConstraint;

@end

@implementation DWBaseSeedViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self baseSeedView_setup];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.scrollView flashScrollIndicators];
}

#pragma mark - Actions

- (void)continueButtonAction:(id)sender {
    // NOP
}

#pragma mark - Private

- (void)baseSeedView_setup {
    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    NSMutableArray<__kindof UIView *> *arrangedSubviews = [NSMutableArray array];

    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.backgroundColor = self.view.backgroundColor;
    scrollView.scrollIndicatorInsets = SCROLL_INDICATOR_INSETS;
    self.scrollView = scrollView;
    [arrangedSubviews addObject:scrollView];

    NSString *continueButtonTitle = NSLocalizedString(@"Continue", nil);
    DWBlueActionButton *bottomContinueButton = nil;
    if (IS_IPHONE_5_OR_LESS) {
        UIBarButtonItem *barButtonItem = [[UIBarButtonItem alloc]
            initWithTitle:continueButtonTitle
                    style:UIBarButtonItemStylePlain
                   target:self
                   action:@selector(continueButtonAction:)];
        self.navigationItem.rightBarButtonItem = barButtonItem;
        self.continueButton = barButtonItem;
    }
    else {
        bottomContinueButton = [[DWBlueActionButton alloc] initWithFrame:CGRectZero];
        bottomContinueButton.translatesAutoresizingMaskIntoConstraints = NO;
        [bottomContinueButton setTitle:continueButtonTitle forState:UIControlStateNormal];
        [bottomContinueButton addTarget:self
                                 action:@selector(continueButtonAction:)
                       forControlEvents:UIControlEventTouchUpInside];
        self.continueButton = bottomContinueButton;
        [arrangedSubviews addObject:bottomContinueButton];
    }

    self.continueButton.enabled = NO;

    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:arrangedSubviews];
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.alignment = UIStackViewAlignmentFill;
    stackView.distribution = UIStackViewDistributionFill;
    stackView.spacing = 16.0;
    [self.view addSubview:stackView];

    UILayoutGuide *marginsGuide = self.view.layoutMarginsGuide;

    const CGFloat bottomPadding = [self.class deviceSpecificBottomPadding];
    self.contentBottomConstraint = [stackView.bottomAnchor constraintEqualToAnchor:marginsGuide.bottomAnchor
                                                                          constant:bottomPadding];

    [NSLayoutConstraint activateConstraints:@[
        [stackView.topAnchor constraintEqualToAnchor:marginsGuide.topAnchor],
        [stackView.leadingAnchor constraintEqualToAnchor:marginsGuide.leadingAnchor],
        [stackView.trailingAnchor constraintEqualToAnchor:marginsGuide.trailingAnchor],
        self.contentBottomConstraint,
    ]];

    if (bottomContinueButton) {
        [bottomContinueButton.heightAnchor constraintEqualToConstant:54.0].active = YES;
    }
}

#pragma mark - Configuration

+ (CGFloat)deviceSpecificBottomPadding {
    if (IS_IPHONE_5_OR_LESS) {
        return 0.0;
    }
    else {
        return [super deviceSpecificBottomPadding];
    }
}

@end

NS_ASSUME_NONNULL_END

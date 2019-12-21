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

#import "DWBlueActionButton.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static UIEdgeInsets const SCROLL_INDICATOR_INSETS = {0.0, 0.0, 0.0, -3.0};
static CGFloat const SPACING = 16.0;
static CGFloat const BOTTOM_BUTTON_HEIGHT = 54.0;

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

@property (nullable, strong, nonatomic) NSLayoutConstraint *contentBottomConstraint;

@end

@implementation DWBaseActionButtonViewController

- (NSString *)actionButtonTitle {
    NSAssert(NO, @"Must be overriden in subclass");
    return nil;
}

- (NSString *)actionButtonDisabledTitle {
    return [self actionButtonTitle];
}

+ (BOOL)showsActionButton {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self baseActionButtonView_setup];
}

- (void)setupContentView:(UIView *)contentView {
    NSParameterAssert(self.stackView);
    NSParameterAssert(contentView);

    [self.stackView insertArrangedSubview:contentView atIndex:0];
}

- (void)reloadActionButtonTitles {
    NSString *actionButtonTitle = [self actionButtonTitle];
    NSString *actionButtonDisabledTitle = [self actionButtonDisabledTitle];
    if (!IS_IPHONE_5_OR_LESS) {
        [(DWBlueActionButton *)self.actionButton setTitle:actionButtonTitle forState:UIControlStateNormal];
        [(DWBlueActionButton *)self.actionButton setTitle:actionButtonDisabledTitle forState:UIControlStateDisabled];
    }
}

#pragma mark - Actions

- (void)actionButtonAction:(id)sender {
    // NOP
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

        if (IS_IPHONE_5_OR_LESS) {
            UIBarButtonItem *barButtonItem = [[UIBarButtonItem alloc]
                initWithTitle:actionButtonTitle
                        style:UIBarButtonItemStylePlain
                       target:self
                       action:@selector(actionButtonAction:)];
            self.navigationItem.rightBarButtonItem = barButtonItem;
            self.actionButton = barButtonItem;
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
        [bottomActionButton.heightAnchor constraintEqualToConstant:BOTTOM_BUTTON_HEIGHT].active = YES;
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

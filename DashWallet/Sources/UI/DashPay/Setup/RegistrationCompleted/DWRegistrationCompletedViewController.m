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

#import "DWRegistrationCompletedViewController.h"

#import "DWActionButton.h"
#import "DWBaseActionButtonViewController.h"
#import "DWUIKit.h"

@interface DWRegistrationCompletedViewController ()

@property (null_resettable, nonatomic, strong) UIImageView *iconImageView;
@property (null_resettable, nonatomic, strong) UILabel *descriptionLabel;
@property (null_resettable, strong, nonatomic) UIButton *actionButton;

@end

@implementation DWRegistrationCompletedViewController

- (void)setUsername:(NSString *)username {
    _username = username;
    [self updateDetailLabel];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_backgroundColor];

    [self.view addSubview:self.iconImageView];
    [self.view addSubview:self.actionButton];

    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ self.descriptionLabel ]];
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    stackView.alignment = UIStackViewAlignmentTop;
    [self.view addSubview:stackView];

    UILayoutGuide *marginsGuide = self.view.layoutMarginsGuide;
    UILayoutGuide *safeAreaGuide = self.view.safeAreaLayoutGuide;

    [self.iconImageView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [self.iconImageView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [stackView setContentHuggingPriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisVertical];

    const CGFloat bottomPadding = [DWBaseActionButtonViewController deviceSpecificBottomPadding];
    [NSLayoutConstraint activateConstraints:@[
        [self.iconImageView.topAnchor constraintEqualToAnchor:marginsGuide.topAnchor],
        [self.iconImageView.leadingAnchor constraintEqualToAnchor:marginsGuide.leadingAnchor],

        [stackView.topAnchor constraintEqualToAnchor:self.iconImageView.bottomAnchor
                                            constant:24.0],
        [stackView.leadingAnchor constraintEqualToAnchor:marginsGuide.leadingAnchor],
        [stackView.trailingAnchor constraintEqualToAnchor:marginsGuide.trailingAnchor],

        [self.actionButton.topAnchor constraintEqualToAnchor:stackView.bottomAnchor],
        [self.actionButton.leadingAnchor constraintEqualToAnchor:marginsGuide.leadingAnchor],
        [self.actionButton.trailingAnchor constraintEqualToAnchor:marginsGuide.trailingAnchor],
        [safeAreaGuide.bottomAnchor constraintEqualToAnchor:self.actionButton.bottomAnchor
                                                   constant:bottomPadding],
        [self.actionButton.heightAnchor constraintEqualToConstant:DWBottomButtonHeight()],
    ]];

    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self
                           selector:@selector(contentSizeCategoryDidChangeNotification)
                               name:UIContentSizeCategoryDidChangeNotification
                             object:nil];
}

#pragma mark - Private

- (UIImageView *)iconImageView {
    if (_iconImageView == nil) {
        UIImageView *imageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"dp_registration_done_icon"]];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconImageView = imageView;
    }
    return _iconImageView;
}

- (UILabel *)descriptionLabel {
    if (_descriptionLabel == nil) {
        UILabel *label = [[UILabel alloc] init];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.numberOfLines = 0;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.5;
        label.contentMode = UIViewContentModeTop;
        _descriptionLabel = label;
    }
    return _descriptionLabel;
}

- (UIButton *)actionButton {
    if (_actionButton == nil) {
        DWActionButton *button = [[DWActionButton alloc] initWithFrame:CGRectZero];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [button setTitle:NSLocalizedString(@"Continue", nil) forState:UIControlStateNormal];
        [button addTarget:self action:@selector(actionButtonAction) forControlEvents:UIControlEventTouchUpInside];
        _actionButton = button;
    }
    return _actionButton;
}

- (void)contentSizeCategoryDidChangeNotification {
    [self updateDetailLabel];
}

- (void)updateDetailLabel {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];

    [result beginEditing];

    NSString *formattedString = [NSString
        stringWithFormat:NSLocalizedString(@"Your username %@ has been successfully created on the Dash Network", nil),
                         self.username];
    NSAttributedString *detail = [[NSAttributedString alloc]
        initWithString:formattedString
            attributes:@{
                NSFontAttributeName : [UIFont dw_regularFontOfSize:26],
                NSForegroundColorAttributeName : [UIColor dw_darkTitleColor],
            }];
    [result appendAttributedString:detail];

    NSRange usernameRange = [formattedString rangeOfString:self.username];
    [result setAttributes:@{
        NSFontAttributeName : [UIFont dw_mediumFontOfSize:26],
        NSForegroundColorAttributeName : [UIColor dw_darkTitleColor],
    }
                    range:usernameRange];

    [result endEditing];

    self.descriptionLabel.attributedText = result;
}

- (void)actionButtonAction {
    [self.delegate registrationCompletedViewControllerAction:self];
}

@end

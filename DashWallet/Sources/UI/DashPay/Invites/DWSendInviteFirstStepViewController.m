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

#import "DWSendInviteFirstStepViewController.h"

#import "DWActionButton.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSendInviteFirstStepViewController ()

@end

NS_ASSUME_NONNULL_END

@implementation DWSendInviteFirstStepViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"Invite", nil);
    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    UIImageView *imageView = [[UIImageView alloc] init];
    imageView.image = [UIImage imageNamed:@"invite_logo"];
    imageView.contentMode = UIViewContentModeCenter;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle3];
    titleLabel.textColor = [UIColor dw_darkTitleColor];
    titleLabel.numberOfLines = 0;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.text = NSLocalizedString(@"Invite your friends & family", nil);
    titleLabel.adjustsFontForContentSizeCategory = YES;

    UILabel *descLabel = [[UILabel alloc] init];
    descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    descLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
    descLabel.textColor = [UIColor dw_darkTitleColor];
    descLabel.numberOfLines = 0;
    descLabel.textAlignment = NSTextAlignmentCenter;
    descLabel.text = NSLocalizedString(@"Let your friends and family to join the Dash Network. Invite them to the world of social banking.", nil);
    descLabel.adjustsFontForContentSizeCategory = YES;

    UIStackView *centerStackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        imageView, titleLabel, descLabel
    ]];
    centerStackView.translatesAutoresizingMaskIntoConstraints = NO;
    centerStackView.axis = UILayoutConstraintAxisVertical;
    centerStackView.spacing = 12.0;
    centerStackView.alignment = UIStackViewAlignmentCenter;
    [centerStackView setCustomSpacing:40 afterView:imageView];
    [self.view addSubview:centerStackView];

    DWActionButton *inviteButton = [[DWActionButton alloc] init];
    inviteButton.translatesAutoresizingMaskIntoConstraints = NO;
    [inviteButton setTitle:NSLocalizedString(@"Create a new Invitation", nil) forState:UIControlStateNormal];
    [inviteButton addTarget:self
                     action:@selector(inviteButtonAction)
           forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:inviteButton];

    UILayoutGuide *guide = self.view.layoutMarginsGuide;
    NSLayoutConstraint *centerConstraint = [centerStackView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor];
    centerConstraint.priority = UILayoutPriorityRequired - 1;
    [NSLayoutConstraint activateConstraints:@[
        [centerStackView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [guide.trailingAnchor constraintEqualToAnchor:centerStackView.trailingAnchor],
        centerConstraint,

        [inviteButton.topAnchor constraintGreaterThanOrEqualToAnchor:centerStackView.bottomAnchor],

        [guide.bottomAnchor constraintEqualToAnchor:inviteButton.bottomAnchor],
        [inviteButton.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [guide.trailingAnchor constraintEqualToAnchor:inviteButton.trailingAnchor],
        [inviteButton.heightAnchor constraintEqualToConstant:50],
    ]];
}

- (void)inviteButtonAction {
    [self.delegate sendInviteFirstStepViewControllerNewInviteAction:self];
}

@end

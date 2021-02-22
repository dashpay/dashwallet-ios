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

#import "DWNoContactsViewController.h"

#import "DWActionButton.h"
#import "DWUIKit.h"

@interface DWNoContactsViewController ()

@end

@implementation DWNoContactsViewController

@synthesize addButton = _addButton;
@synthesize inviteButton = _inviteButton;

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    UIImageView *imageView = [[UIImageView alloc] init];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.image = [UIImage imageNamed:@"no_contacts_placeholder"];
    imageView.contentMode = UIViewContentModeCenter;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
    titleLabel.textColor = [UIColor dw_secondaryTextColor];
    titleLabel.numberOfLines = 0;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.text = NSLocalizedString(@"You do not have any contacts at the moment", nil);
    titleLabel.adjustsFontForContentSizeCategory = YES;

    DWActionButton *addButton = [[DWActionButton alloc] init];
    addButton.translatesAutoresizingMaskIntoConstraints = NO;
    [addButton setTitle:NSLocalizedString(@"Add a New Contact", nil) forState:UIControlStateNormal];

    UIStackView *centerStackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        imageView, titleLabel, addButton
    ]];
    centerStackView.translatesAutoresizingMaskIntoConstraints = NO;
    centerStackView.axis = UILayoutConstraintAxisVertical;
    centerStackView.spacing = 24.0;
    centerStackView.alignment = UIStackViewAlignmentCenter;
    [self.view addSubview:centerStackView];

    UILabel *orLabel = [[UILabel alloc] init];
    orLabel.translatesAutoresizingMaskIntoConstraints = NO;
    orLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];
    orLabel.textColor = [UIColor dw_tertiaryTextColor];
    orLabel.textAlignment = NSTextAlignmentCenter;
    orLabel.text = NSLocalizedString(@"or", nil);
    orLabel.adjustsFontForContentSizeCategory = YES;

    UIImageView *inviteImageView = [[UIImageView alloc] init];
    inviteImageView.translatesAutoresizingMaskIntoConstraints = NO;
    inviteImageView.image = [UIImage imageNamed:@"menu_invite"];
    inviteImageView.contentMode = UIViewContentModeCenter;

    DWActionButton *inviteButton = [[DWActionButton alloc] init];
    inviteButton.translatesAutoresizingMaskIntoConstraints = NO;
    inviteButton.inverted = YES;
    [inviteButton setTitle:NSLocalizedString(@"Invite Someone to join the Dash Network", nil) forState:UIControlStateNormal];

    UIStackView *bottomStackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        orLabel, inviteImageView, inviteButton
    ]];
    bottomStackView.translatesAutoresizingMaskIntoConstraints = NO;
    bottomStackView.axis = UILayoutConstraintAxisVertical;
    bottomStackView.spacing = 4;
    [self.view addSubview:bottomStackView];

    UILayoutGuide *guide = self.view.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [centerStackView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [guide.trailingAnchor constraintEqualToAnchor:centerStackView.trailingAnchor],
        [centerStackView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [bottomStackView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [guide.trailingAnchor constraintEqualToAnchor:bottomStackView.trailingAnchor],
        [guide.bottomAnchor constraintEqualToAnchor:bottomStackView.bottomAnchor],

        [addButton.heightAnchor constraintEqualToConstant:50],
        [inviteButton.heightAnchor constraintEqualToConstant:44],
        [addButton.widthAnchor constraintEqualToAnchor:centerStackView.widthAnchor
                                            multiplier:0.8],
    ]];

    _addButton = addButton;
    _inviteButton = inviteButton;
}

@end

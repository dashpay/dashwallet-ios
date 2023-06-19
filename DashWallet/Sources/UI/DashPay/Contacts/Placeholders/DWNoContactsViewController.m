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
#import "DWGlobalOptions.h"
#import "DWInvitationSuggestionView.h"
#import "DWUIKit.h"

@interface DWNoContactsViewController ()

@property (null_resettable, strong, nonatomic) DWInvitationSuggestionView *invitationView;

@end

@implementation DWNoContactsViewController

@synthesize addButton = _addButton;

- (UIButton *)inviteButton {
    return self.invitationView.inviteButton;
}

- (DWInvitationSuggestionView *)invitationView {
    if (!_invitationView) {
        _invitationView = [[DWInvitationSuggestionView alloc] init];
        _invitationView.translatesAutoresizingMaskIntoConstraints = NO;
        _invitationView.alpha = [DWGlobalOptions sharedInstance].dpInvitationFlowEnabled ? 1.0 : 0.0;
    }
    return _invitationView;
}

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

    [self.view addSubview:self.invitationView];

    UILayoutGuide *guide = self.view.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [centerStackView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [guide.trailingAnchor constraintEqualToAnchor:centerStackView.trailingAnchor],
        [centerStackView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [self.invitationView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [guide.trailingAnchor constraintEqualToAnchor:self.invitationView.trailingAnchor],
        [guide.bottomAnchor constraintEqualToAnchor:self.invitationView.bottomAnchor],

        [addButton.heightAnchor constraintEqualToConstant:50],
        [addButton.widthAnchor constraintEqualToAnchor:centerStackView.widthAnchor
                                            multiplier:0.8],
    ]];

    _addButton = addButton;
}

@end

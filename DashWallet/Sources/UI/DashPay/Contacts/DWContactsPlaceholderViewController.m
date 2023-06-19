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

#import "DWContactsPlaceholderViewController.h"

#import "DWDashPayModel.h"
#import "DWDashPaySetupFlowController.h"
#import "DWUIKit.h"

@interface DWContactsPlaceholderViewController ()

@property (readonly, nonatomic, strong) id<DWDashPayProtocol> dashPayModel;
@property (readonly, nonatomic, strong) id<DWDashPayReadyProtocol> dashPayReady;

@end

@implementation DWContactsPlaceholderViewController

- (instancetype)initWithDashPayModel:(id<DWDashPayProtocol>)dashPayModel dashPayReady:(id<DWDashPayReadyProtocol>)dashPayReady {
    self = [super init];
    if (self) {
        _dashPayModel = dashPayModel;
        _dashPayReady = dashPayReady;
    }
    return self;
}

- (NSString *)actionButtonTitle {
    return NSLocalizedString(@"Upgrade", nil);
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    UIImageView *imageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"contacts_placeholder_icon"]];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.contentMode = UIViewContentModeCenter;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle3];
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.text = NSLocalizedString(@"Upgrade to Evolution", nil);
    titleLabel.textColor = [UIColor dw_darkTitleColor];
    titleLabel.numberOfLines = 0;

    UILabel *descriptionLabel = [[UILabel alloc] init];
    descriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    descriptionLabel.textAlignment = NSTextAlignmentCenter;
    descriptionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
    descriptionLabel.adjustsFontForContentSizeCategory = YES;
    descriptionLabel.text = NSLocalizedString(@"Create your Username, find friends & family with their usernames and add them to your contacts", nil);
    descriptionLabel.textColor = [UIColor dw_tertiaryTextColor];
    descriptionLabel.numberOfLines = 0;

    UIStackView *verticalStackView = [[UIStackView alloc] initWithArrangedSubviews:@[ imageView, titleLabel, descriptionLabel ]];
    verticalStackView.translatesAutoresizingMaskIntoConstraints = NO;
    verticalStackView.axis = UILayoutConstraintAxisVertical;
    verticalStackView.spacing = 4.0;
    [verticalStackView setCustomSpacing:26.0 afterView:imageView];

    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.backgroundColor = self.view.backgroundColor;
    [contentView addSubview:verticalStackView];

    [NSLayoutConstraint activateConstraints:@[
        [verticalStackView.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],
        [verticalStackView.topAnchor constraintGreaterThanOrEqualToAnchor:contentView.topAnchor],
        [contentView.bottomAnchor constraintGreaterThanOrEqualToAnchor:contentView.bottomAnchor],
        [verticalStackView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:verticalStackView.trailingAnchor],
    ]];

    [self setupContentView:contentView];

    // Model:

    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self
                           selector:@selector(update)
                               name:DWDashPayRegistrationStatusUpdatedNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(update)
                               name:DWDashPayAvailabilityStatusUpdatedNotification
                             object:nil];

    [self update];
}

- (void)actionButtonAction:(id)sender {
    DWDashPaySetupFlowController *controller =
        [[DWDashPaySetupFlowController alloc]
            initWithDashPayModel:self.dashPayModel
                      invitation:nil
                 definedUsername:nil];
    controller.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)update {
    self.actionButton.enabled = [self.dashPayReady isDashPayReady];
}

@end

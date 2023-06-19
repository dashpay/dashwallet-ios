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

#import "DWInvitationPreviewViewController.h"

#import "DSBlockchainIdentity+DWDisplayName.h"
#import "DWActionButton.h"
#import "DWEnvironment.h"
#import "DWModalPopupTransition.h"
#import "DWSuccessInvitationView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWInvitationPreviewViewController ()

@property (nonatomic, strong) DWModalPopupTransition *modalTransition;

@property (readonly, nonatomic, strong) DWSuccessInvitationView *iconView;

@end

NS_ASSUME_NONNULL_END

@implementation DWInvitationPreviewViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _modalTransition = [[DWModalPopupTransition alloc] initWithInteractiveTransitionAllowed:YES];

        self.transitioningDelegate = self.modalTransition;
        self.modalPresentationStyle = UIModalPresentationCustom;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor clearColor];

    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.backgroundColor = [UIColor dw_backgroundColor];
    contentView.layer.cornerRadius = 8.0;
    contentView.layer.masksToBounds = YES;
    [self.view addSubview:contentView];


    DWSuccessInvitationView *iconView = [[DWSuccessInvitationView alloc] initWithFrame:CGRectZero];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:iconView];
    _iconView = iconView;

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.textColor = [UIColor dw_dashBlueColor];
    title.text = NSLocalizedString(@"Join Now", nil);
    title.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle2];
    title.textAlignment = NSTextAlignmentCenter;
    title.numberOfLines = 0;
    [contentView addSubview:title];

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.textColor = [UIColor dw_darkTitleColor];
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.numberOfLines = 0;
    [contentView addSubview:subtitle];

    DWActionButton *okButton = [[DWActionButton alloc] initWithFrame:CGRectZero];
    okButton.translatesAutoresizingMaskIntoConstraints = NO;
    okButton.usedOnDarkBackground = NO;
    okButton.small = YES;
    okButton.inverted = YES;
    [okButton setTitle:NSLocalizedString(@"Close", nil) forState:UIControlStateNormal];
    [okButton addTarget:self action:@selector(closeButtonAction:) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:okButton];

    [NSLayoutConstraint activateConstraints:@[
        [contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [contentView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [iconView.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                           constant:32.0],
        [iconView.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],

        [title.topAnchor constraintEqualToAnchor:iconView.bottomAnchor
                                        constant:28],
        [title.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                            constant:16],
        [contentView.trailingAnchor constraintEqualToAnchor:title.trailingAnchor
                                                   constant:16],

        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor
                                           constant:16],
        [subtitle.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                               constant:16],
        [contentView.trailingAnchor constraintEqualToAnchor:subtitle.trailingAnchor
                                                   constant:16],

        [okButton.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor
                                           constant:32.0],
        [okButton.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:okButton.bottomAnchor
                                                 constant:20.0],
        [okButton.heightAnchor constraintGreaterThanOrEqualToConstant:40.0],
    ]];

    // Setup
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;
    iconView.blockchainIdentity = myBlockchainIdentity;

    NSMutableAttributedString *desc = [[NSMutableAttributedString alloc] init];
    [desc beginEditing];

    NSString *name = [myBlockchainIdentity dw_displayNameOrUsername];
    NSString *text = [NSString stringWithFormat:NSLocalizedString(@"You have been invited by %@. Start using Dash cryptocurrency.", nil), name];

    [desc appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleBody]}]];
    NSRange range = [text rangeOfString:name];
    if (range.location != NSNotFound) {
        [desc setAttributes:@{NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline]} range:range];
    }

    [desc endEditing];
    subtitle.attributedText = desc;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self.iconView prepareForAnimation];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.iconView showAnimated];
}

- (void)closeButtonAction:(UIButton *)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

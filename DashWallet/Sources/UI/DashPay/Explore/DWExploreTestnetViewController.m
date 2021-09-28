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

#import "DWExploreTestnetViewController.h"

#import "DWColoredButton.h"
#import "DWEnvironment.h"
#import "DWExploreHeaderView.h"
#import "DWExploreTestnetContentsView.h"
#import "DWScrollingViewController.h"
#import "DWUIKit.h"

@implementation DWExploreTestnetViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_darkBlueColor];

    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:contentView];

    UIView *footerView = [[UIView alloc] init];
    footerView.translatesAutoresizingMaskIntoConstraints = NO;
    footerView.backgroundColor = [UIColor dw_backgroundColor];
    [self.view addSubview:footerView];

    DWColoredButton *actionButton = [[DWColoredButton alloc] init];
    actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    actionButton.style = DWColoredButtonStyle_Black;
    [actionButton setTitle:NSLocalizedString(@"Get Test Dash", nil) forState:UIControlStateNormal];
    [actionButton addTarget:self action:@selector(buttonAction) forControlEvents:UIControlEventTouchUpInside];
    [footerView addSubview:actionButton];

    CGFloat padding = 16.0;
    [NSLayoutConstraint activateConstraints:@[
        [contentView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.view.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],

        [footerView.topAnchor constraintEqualToAnchor:contentView.bottomAnchor],
        [footerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.view.trailingAnchor constraintEqualToAnchor:footerView.trailingAnchor],
        [self.view.bottomAnchor constraintEqualToAnchor:footerView.bottomAnchor],

        [actionButton.topAnchor constraintEqualToAnchor:footerView.topAnchor
                                               constant:padding],
        [actionButton.leadingAnchor constraintEqualToAnchor:footerView.leadingAnchor
                                                   constant:padding],
        [footerView.trailingAnchor constraintEqualToAnchor:actionButton.trailingAnchor
                                                  constant:padding],
        [footerView.bottomAnchor constraintEqualToAnchor:actionButton.bottomAnchor
                                                constant:padding],

        [actionButton.heightAnchor constraintEqualToConstant:46.0],
    ]];

    // Contents

    DWExploreHeaderView *headerView = [[DWExploreHeaderView alloc] init];
    headerView.translatesAutoresizingMaskIntoConstraints = NO;
    headerView.image = [UIImage imageNamed:@"image.explore.dash.wallet"];
    headerView.title = NSLocalizedString(@"Explore Dash", nil);
    headerView.subtitle = NSLocalizedString(@"Test Dash doesn’t have any value in the real world but you can send and receive it with other DashPay Alpha users.", nil);

    DWExploreTestnetContentsView *contentsView = [[DWExploreTestnetContentsView alloc] init];
    contentsView.translatesAutoresizingMaskIntoConstraints = NO;

    DWScrollingViewController *scrollingController = [[DWScrollingViewController alloc] init];
    scrollingController.keyboardNotificationsEnabled = NO;

    [self dw_embedChild:scrollingController inContainer:contentView];

    UIView *parentView = scrollingController.contentView;

    UIView *overscrollView = [[UIView alloc] init];
    overscrollView.translatesAutoresizingMaskIntoConstraints = NO;
    overscrollView.backgroundColor = [UIColor dw_backgroundColor];
    [parentView addSubview:overscrollView];

    [parentView addSubview:headerView];
    [parentView addSubview:contentsView];

    [NSLayoutConstraint activateConstraints:@[
        [headerView.topAnchor constraintEqualToAnchor:parentView.topAnchor],
        [headerView.leadingAnchor constraintEqualToAnchor:parentView.leadingAnchor],
        [parentView.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor],

        [contentsView.topAnchor constraintEqualToAnchor:headerView.bottomAnchor],
        [contentsView.leadingAnchor constraintEqualToAnchor:parentView.leadingAnchor],
        [parentView.trailingAnchor constraintEqualToAnchor:contentsView.trailingAnchor],
        [parentView.bottomAnchor constraintEqualToAnchor:contentsView.bottomAnchor],

        [overscrollView.topAnchor constraintEqualToAnchor:contentsView.bottomAnchor
                                                 constant:-10],
        [overscrollView.leadingAnchor constraintEqualToAnchor:parentView.leadingAnchor],
        [parentView.trailingAnchor constraintEqualToAnchor:overscrollView.trailingAnchor],
        [overscrollView.heightAnchor constraintEqualToConstant:500],
    ]];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)buttonAction {
    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
    NSString *paymentAddress = account.receiveAddress;
    if (paymentAddress == nil) {
        return;
    }

    [UIPasteboard generalPasteboard].string = paymentAddress;
    NSURL *url = [NSURL URLWithString:@"https://testnet-faucet.dash.org/"];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

@end

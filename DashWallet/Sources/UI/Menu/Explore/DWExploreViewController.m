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

#import "DWExploreViewController.h"

#import "DWActionButton.h"
#import "DWEnvironment.h"
#import "DWExploreContentsView.h"
#import "DWExploreHeaderView.h"
#import "DWScrollingViewController.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWExploreViewController () <DWExploreContentsViewDelegate>

@end

NS_ASSUME_NONNULL_END

@implementation DWExploreViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_darkBlueColor];

    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:contentView];

    UIButton *backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [backButton setImage:[UIImage imageNamed:@"backbutton"] forState:UIControlStateNormal];
    backButton.tintColor = [UIColor whiteColor];
    [backButton addTarget:self action:@selector(backButtonAction) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:backButton];

    CGFloat padding = 16.0;
    [NSLayoutConstraint activateConstraints:@[
        [contentView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.view.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.view.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],

        [backButton.topAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.topAnchor],
        [backButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [backButton.widthAnchor constraintEqualToConstant:44],
        [backButton.heightAnchor constraintEqualToConstant:44],
    ]];

    // Contents

    DWExploreHeaderView *headerView = [[DWExploreHeaderView alloc] init];
    headerView.translatesAutoresizingMaskIntoConstraints = NO;
    headerView.image = [UIImage imageNamed:@"explore_icon"];
    headerView.title = NSLocalizedString(@"Explore Dash", nil);
    headerView.subtitle = NSLocalizedString(@"Easily shop with your DASH at over 155,000 locations and online merchants", nil);

    DWExploreContentsView *contentsView = [[DWExploreContentsView alloc] init];
    contentsView.delegate = self;
    contentsView.translatesAutoresizingMaskIntoConstraints = NO;

    DWScrollingViewController *scrollingController = [[DWScrollingViewController alloc] init];
    scrollingController.keyboardNotificationsEnabled = NO;

    [self dw_embedChild:scrollingController inContainer:contentView];

    UIView *parentView = scrollingController.contentView;

    UIView *overscrollView = [[UIView alloc] init];
    overscrollView.translatesAutoresizingMaskIntoConstraints = NO;
    overscrollView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
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

- (BOOL)requiresNoNavigationBar {
    return YES;
}

- (void)backButtonAction {
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - DWExploreContentsViewDelegate

- (void)exploreContentsView:(DWExploreContentsView *)view spendButtonAction:(UIControl *)sender {
    // TODO: impl
}

- (void)exploreContentsView:(DWExploreContentsView *)view atmButtonAction:(UIControl *)sender {
    // TODO: impl
}

@end

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

#import "DWHistoryFilterViewController.h"

#import "DWHistoryFilterContentView.h"
#import "DWModalPopupTransition.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWHistoryFilterViewController () <DWHistoryFilterContentViewDelegate>

@property (nonatomic, strong) DWModalPopupTransition *modalTransition;

@end

NS_ASSUME_NONNULL_END

@implementation DWHistoryFilterViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _modalTransition = [[DWModalPopupTransition alloc] init];
        _modalTransition.appearanceStyle = DWModalPopupAppearanceStyle_Fullscreen;

        self.transitioningDelegate = self.modalTransition;
        self.modalPresentationStyle = UIModalPresentationCustom;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapRecognizerAction)];
    [self.view addGestureRecognizer:tapRecognizer];

    DWHistoryFilterContentView *contentView = [[DWHistoryFilterContentView alloc] initWithFrame:CGRectZero];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.delegate = self;
    [self.view addSubview:contentView];

    UIView *overscroll = [[UIView alloc] init];
    overscroll.translatesAutoresizingMaskIntoConstraints = NO;
    overscroll.backgroundColor = [UIColor dw_backgroundColor];
    [self.view addSubview:overscroll];

    [NSLayoutConstraint activateConstraints:@[
        [contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.view.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.view.safeAreaLayoutGuide.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],

        [overscroll.topAnchor constraintEqualToAnchor:contentView.bottomAnchor
                                             constant:-10],
        [overscroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.view.trailingAnchor constraintEqualToAnchor:overscroll.trailingAnchor],
        [overscroll.heightAnchor constraintEqualToConstant:500],
    ]];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)tapRecognizerAction {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - DWHistoryFilterContentViewDelegate

- (void)historyFilterView:(DWHistoryFilterContentView *)view didSelectFilter:(DWInvitationHistoryFilter)filter {
    [self.delegate historyFilterViewController:self didSelectFilter:filter];
}

@end

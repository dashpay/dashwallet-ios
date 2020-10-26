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

#import "DWTxDetailFullscreenViewController.h"

#import "DWModalPopupTransition.h"
#import "DWTxDetailViewController.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWTxDetailFullscreenViewController () <DWTxDetailViewControllerDelegate>

@property (readonly, nonatomic, strong) DSTransaction *transaction;
@property (readonly, nonatomic, strong) id<DWTransactionListDataProviderProtocol> dataProvider;

@property (nonatomic, strong) DWModalPopupTransition *modalTransition;
@property (nonatomic, strong) DWTxDetailViewController *detailController;

@end

@implementation DWTxDetailFullscreenViewController

- (instancetype)initWithTransaction:(DSTransaction *)transaction
                       dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _transaction = transaction;
        _dataProvider = dataProvider;

        _modalTransition = [[DWModalPopupTransition alloc] init];
        _modalTransition.appearanceStyle = DWModalPopupAppearanceStyle_Fullscreen;

        self.transitioningDelegate = self.modalTransition;
        self.modalPresentationStyle = UIModalPresentationCustom;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

#pragma mark - DWTxDetailViewControllerDelegate

- (void)txDetailViewController:(DWTxDetailViewController *)controller closeButtonAction:(UIButton *)sender {
    [self.delegate detailFullscreenViewControllerDidFinish:self];
}

- (void)txDetailViewController:(DWTxDetailViewController *)controller openUserItem:(id<DWDPBasicUserItem>)userItem {
    // NOP
    // Opening user profile from the fullscreen is not supported here because
    // it will be opened automatically after payment.
}

#pragma mark - Private

- (void)setupView {
    self.view.backgroundColor = [UIColor dw_backgroundColor];

    DWTxDetailViewController *controller =
        [[DWTxDetailViewController alloc] initWithTransaction:self.transaction
                                                 dataProvider:self.dataProvider
                                          displayingAsDetails:NO];
    controller.delegate = self;

    [self addChildViewController:controller];

    UIView *childView = controller.view;
    UIView *contentView = self.view;

    childView.translatesAutoresizingMaskIntoConstraints = NO;
    childView.preservesSuperviewLayoutMargins = YES;
    [contentView addSubview:childView];

    const CGRect bounds = [UIScreen mainScreen].bounds;
    const CGFloat width = MIN(CGRectGetWidth(bounds), CGRectGetHeight(bounds));
    CGFloat viewWidth;
    if (IS_IPAD) {
        viewWidth = width / 2;
    }
    else {
        const CGFloat horizontalPadding = 16.0;
        viewWidth = width - horizontalPadding * 2;
    }

    const CGFloat verticalPadding = 16.0;

    [NSLayoutConstraint activateConstraints:@[
        [childView.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [childView.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],
        [childView.widthAnchor constraintEqualToConstant:viewWidth],
        [childView.topAnchor constraintGreaterThanOrEqualToAnchor:contentView.topAnchor
                                                         constant:verticalPadding],
        [childView.bottomAnchor constraintGreaterThanOrEqualToAnchor:contentView.bottomAnchor
                                                            constant:-verticalPadding],
    ]];

    [controller didMoveToParentViewController:self];
}

@end

NS_ASSUME_NONNULL_END

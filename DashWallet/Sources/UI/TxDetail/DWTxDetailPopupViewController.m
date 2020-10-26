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

#import "DWTxDetailPopupViewController.h"

#import "DWModalPopupTransition.h"
#import "DWTxDetailViewController.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const CORNER_RADIUS = 8.0;

static CGFloat VerticalPadding(void) {
    if (IS_IPAD) {
        return 32.0;
    }
    else if (IS_IPHONE_6 || IS_IPHONE_5_OR_LESS) {
        return 16.0;
    }
    else {
        return 24.0;
    }
}

@interface DWTxDetailPopupViewController () <DWTxDetailViewControllerDelegate>

@property (readonly, nonatomic, strong) DSTransaction *transaction;
@property (readonly, nonatomic, strong) id<DWTransactionListDataProviderProtocol> dataProvider;

@property (nonatomic, strong) DWModalPopupTransition *modalTransition;

@end

@implementation DWTxDetailPopupViewController

- (instancetype)initWithTransaction:(DSTransaction *)transaction
                       dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _transaction = transaction;
        _dataProvider = dataProvider;

        _modalTransition = [[DWModalPopupTransition alloc] init];

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
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)txDetailViewController:(DWTxDetailViewController *)controller openUserItem:(id<DWDPBasicUserItem>)userItem {
    [self.delegate txDetailPopupViewController:self openUserItem:userItem];
}

#pragma mark - Private

- (void)setupView {
    self.view.backgroundColor = [UIColor dw_backgroundColor];
    self.view.clipsToBounds = YES;
    self.view.layer.cornerRadius = CORNER_RADIUS;

    DWTxDetailViewController *controller =
        [[DWTxDetailViewController alloc] initWithTransaction:self.transaction
                                                 dataProvider:self.dataProvider
                                          displayingAsDetails:YES];
    controller.delegate = self;

    [self addChildViewController:controller];

    UIView *childView = controller.view;
    UIView *contentView = self.view;

    childView.translatesAutoresizingMaskIntoConstraints = NO;
    childView.preservesSuperviewLayoutMargins = YES;
    [contentView addSubview:childView];

    const CGFloat padding = VerticalPadding();
    [NSLayoutConstraint activateConstraints:@[
        [childView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [childView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [childView.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],
        [childView.topAnchor constraintGreaterThanOrEqualToAnchor:contentView.topAnchor
                                                         constant:padding],
        [childView.bottomAnchor constraintGreaterThanOrEqualToAnchor:contentView.bottomAnchor
                                                            constant:-padding],
    ]];

    [controller didMoveToParentViewController:self];
}

@end

NS_ASSUME_NONNULL_END

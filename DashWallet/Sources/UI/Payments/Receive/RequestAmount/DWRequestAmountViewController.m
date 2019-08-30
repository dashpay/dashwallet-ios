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

#import "DWRequestAmountViewController.h"

#import "DWReceiveModel.h"
#import "DWRequestAmountContentView.h"
#import "UIViewController+DWShareReceiveInfo.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWRequestAmountViewController () <DWRequestAmountContentViewDelegate>

@property (nonatomic, strong) DWReceiveModel *model;
@property (nonatomic, strong) DWRequestAmountContentView *requestAmountView;

@end

@implementation DWRequestAmountViewController

+ (instancetype)controllerWithModel:(DWReceiveModel *)model {
    DWRequestAmountViewController *controller = [[DWRequestAmountViewController alloc] init];
    controller.model = model;

    return controller;
}

+ (BOOL)showsActionButton {
    return NO;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];

    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self
                           selector:@selector(checkRequestStatus)
                               name:DSWalletBalanceDidChangeNotification
                             object:nil];

    [notificationCenter addObserver:self
                           selector:@selector(checkRequestStatus)
                               name:DSTransactionManagerTransactionStatusDidChangeNotification
                             object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.requestAmountView viewDidAppear];
}

#pragma mark - DWRequestAmountContentViewDelegate

- (void)requestAmountContentView:(DWRequestAmountContentView *)view shareButtonAction:(UIButton *)sender {
    [self dw_shareReceiveInfo:self.model sender:sender];
}

#pragma mark - Notifications

- (void)checkRequestStatus {
    NSString *_Nullable receivedInfo = [self.model requestAmountReceivedInfoIfReceived];
    if (receivedInfo) {
        [self.delegate requestAmountViewController:self didReceiveAmountWithInfo:receivedInfo];
    }
}

#pragma mark - Private

- (void)setupView {
    [self setModalTitle:NSLocalizedString(@"Receive", nil)];

    [self setupModalContentView:self.requestAmountView];
}

- (DWRequestAmountContentView *)requestAmountView {
    if (_requestAmountView == nil) {
        _requestAmountView = [[DWRequestAmountContentView alloc] initWithModel:self.model];
        _requestAmountView.delegate = self;
    }

    return _requestAmountView;
}


@end

NS_ASSUME_NONNULL_END

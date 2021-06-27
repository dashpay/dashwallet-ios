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

#import "DWPayViewController.h"

#import "DWConfirmPaymentViewController.h"
#import "DWPayModelProtocol.h"
#import "DWPayOptionModel.h"
#import "DWPayTableViewCell.h"
#import "DWPaymentInputBuilder.h"
#import "DWPaymentProcessor.h"
#import "DWQRScanModel.h"
#import "DWQRScanViewController.h"
#import "DWSendAmountViewController.h"
#import "DWUIKit.h"
#import "UIView+DWHUD.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWPayViewController () <UITableViewDataSource,
                                   UITableViewDelegate,
                                   DWPayTableViewCellDelegate>

@property (strong, nonatomic) IBOutlet UITableView *tableView;
@property (assign, nonatomic) CGFloat maxActionButtonWidth;

@end

@implementation DWPayViewController

+ (instancetype)controllerWithModel:(id<DWPayModelProtocol>)payModel
                       dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Pay" bundle:nil];
    DWPayViewController *controller = [storyboard instantiateInitialViewController];
    controller.payModel = payModel;
    controller.dataProvider = dataProvider;

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.tableView flashScrollIndicators];

    if (self.demoMode) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self performPayToPasteboardAction];
        });
    }
}

- (void)payViewControllerDidHidePaymentResultToContact:(nullable id<DWDPBasicUserItem>)contact {
    [self.delegate payViewControllerDidFinishPayment:self contact:contact];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.payModel.options.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = DWPayTableViewCell.dw_reuseIdentifier;
    DWPayTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId forIndexPath:indexPath];

    DWPayOptionModel *option = self.payModel.options[indexPath.row];
    cell.delegate = self;
    cell.model = option;

    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([cell isKindOfClass:DWPayTableViewCell.class]) {
        DWPayTableViewCell *payCell = (DWPayTableViewCell *)cell;
        payCell.preferredActionButtonWidth = self.maxActionButtonWidth;
    }
}

#pragma mark - DWPayTableViewCellDelegate

- (void)payTableViewCell:(DWPayTableViewCell *)cell action:(UIButton *)sender {
    DWPayOptionModel *payOption = cell.model;
    NSParameterAssert(payOption);
    if (!payOption) {
        return;
    }

    switch (payOption.type) {
        case DWPayOptionModelType_ScanQR: {
            [self performScanQRCodeAction];

            break;
        }
        case DWPayOptionModelType_Pasteboard: {
            [self payToAddressAction];

            break;
        }
        case DWPayOptionModelType_NFC: {
            [self performNFCReadingAction];

            break;
        }
    }
}

- (void)payTableViewCell:(DWPayTableViewCell *)cell didUpdateButtonWidth:(CGFloat)buttonWidth {
    self.maxActionButtonWidth = MAX(self.maxActionButtonWidth, buttonWidth);
}

#pragma mark - Private

- (void)setupView {
    NSString *cellId = DWPayTableViewCell.dw_reuseIdentifier;
    UINib *nib = [UINib nibWithNibName:cellId bundle:nil];
    NSParameterAssert(nib);
    [self.tableView registerNib:nib forCellReuseIdentifier:cellId];

    self.tableView.tableFooterView = [[UIView alloc] init];
}


@end

NS_ASSUME_NONNULL_END

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

#import "DWPayModel.h"
#import "DWPayOptionModel.h"
#import "DWPayTableViewCell.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWPayViewController () <UITableViewDataSource, DWPayTableViewCellDelegate>

@property (strong, nonatomic) IBOutlet UITableView *tableView;

@property (strong, nonatomic) DWPayModel *model;

@end

@implementation DWPayViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Pay" bundle:nil];
    DWPayViewController *controller = [storyboard instantiateInitialViewController];
    controller.model = [[DWPayModel alloc] init];

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.tableView flashScrollIndicators];

    [self.model startPasteboardIntervalObserving];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];

    [self.model stopPasteboardIntervalObserving];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.model.options.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = DWPayTableViewCell.dw_reuseIdentifier;
    DWPayTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId forIndexPath:indexPath];

    DWPayOptionModel *option = self.model.options[indexPath.row];
    cell.model = option;
    cell.delegate = self;

    return cell;
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
            // TODO: show qr screen
            break;
        }
        case DWPayOptionModelType_Pasteboard: {
            NSParameterAssert(self.model.pasteboardPaymentInput);
            // TODO: impl logic from DWSendViewController
            // - (void)confirmRequest:(DSPaymentRequest *)request
            // - (void)confirmProtocolRequest:(DSPaymentProtocolRequest *)protoReq

            break;
        }
        case DWPayOptionModelType_NFC: {
            __weak typeof(self) weakSelf = self;
            [self.model performNFCReadingWithCompletion:^(DWPaymentInput *_Nonnull paymentInput) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }

                // TODO: impl logic from DWSendViewController
                // - (void)confirmRequest:(DSPaymentRequest *)request
                // - (void)confirmProtocolRequest:(DSPaymentProtocolRequest *)protoReq
            }];

            break;
        }
    }
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

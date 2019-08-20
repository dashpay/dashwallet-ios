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
#import "DWPaymentInputBuilder.h"
#import "DWPaymentProcessor.h"
#import "DWSendAmountViewController.h"
#import "DWUIKit.h"
#import "UIView+DWHUD.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWPayViewController () <UITableViewDataSource,
                                   DWPayTableViewCellDelegate,
                                   DWPaymentInputProcessorDelegate,
                                   DWSendAmountViewControllerDelegate>

@property (strong, nonatomic) IBOutlet UITableView *tableView;

@property (strong, nonatomic) DWPayModel *model;
@property (nonatomic, strong) DWPaymentProcessor *paymentProcessor;

@end

@implementation DWPayViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Pay" bundle:nil];
    DWPayViewController *controller = [storyboard instantiateInitialViewController];
    controller.model = [[DWPayModel alloc] init];
    controller.paymentProcessor = [[DWPaymentProcessor alloc] init];

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
            DWPaymentInput *paymentInput = self.model.pasteboardPaymentInput;
            NSParameterAssert(paymentInput);
            [self.paymentProcessor processPaymentInput:paymentInput];

            break;
        }
        case DWPayOptionModelType_NFC: {
            __weak typeof(self) weakSelf = self;
            [self.model performNFCReadingWithCompletion:^(DWPaymentInput *_Nonnull paymentInput) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }

                [strongSelf.paymentProcessor processPaymentInput:paymentInput];
            }];

            break;
        }
    }
}

#pragma mark - DWPaymentInputProcessorDelegate

// User Actions

- (void)paymentProcessor:(DWPaymentProcessor *)processor
    requestAmountWithDestination:(NSString *)sendingDestination
                         details:(nullable DSPaymentProtocolDetails *)details {
    DWSendAmountViewController *controller =
        [DWSendAmountViewController sendControllerWithDestination:sendingDestination
                                                   paymentDetails:nil];
    controller.delegate = self;
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)paymentProcessor:(DWPaymentProcessor *)processor
    requestUserActionTitle:(nullable NSString *)title
                   message:(nullable NSString *)message
               actionTitle:(NSString *)actionTitle
               cancelBlock:(void (^)(void))cancelBlock
               actionBlock:(void (^)(void))actionBlock {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:title
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *cancelAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"Cancel", nil)
                  style:UIAlertActionStyleCancel
                handler:^(UIAlertAction *action) {
                    NSParameterAssert(cancelBlock);
                    if (cancelBlock) {
                        cancelBlock();
                    }
                }];
    [alert addAction:cancelAction];

    UIAlertAction *actionAction = [UIAlertAction
        actionWithTitle:actionTitle
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    NSParameterAssert(actionBlock);
                    if (actionBlock) {
                        actionBlock();
                    }
                }];
    [alert addAction:actionAction];

    [self.navigationController presentViewController:alert animated:YES completion:nil];
}

// Result

- (void)paymentInputProcessorHideAmountControllerIfNeeded:(nonnull DWPaymentProcessor *)processor {
    if ([self.navigationController.topViewController isKindOfClass:DWSendAmountViewController.class]) {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)paymentProcessor:(DWPaymentProcessor *)processor
       didFailWithReason:(nullable NSString *)reason
             description:(nullable NSString *)description {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:reason
                         message:description
                  preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"OK", nil)
                  style:UIAlertActionStyleCancel
                handler:nil];
    [alert addAction:okAction];
    [self.navigationController presentViewController:alert animated:YES completion:nil];
}

- (void)paymentProcessor:(DWPaymentProcessor *)processor
          didSendRequest:(DSPaymentProtocolRequest *)protocolRequest
             transaction:(DSTransaction *)transaction {
    NSLog(@">>>> ### %@", NSStringFromSelector(_cmd));
}

- (void)paymentProcessor:(nonnull DWPaymentProcessor *)processor
         didSweepRequest:(nonnull DSPaymentRequest *)protocolRequest
             transaction:(nonnull DSTransaction *)transaction {
    NSLog(@">>>> ### %@", NSStringFromSelector(_cmd));
}

// Handle File

- (void)paymentProcessor:(DWPaymentProcessor *)processor
    displayFileProcessResult:(NSString *)result {
    NSLog(@">>>> ### %@", NSStringFromSelector(_cmd));
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:result
                         message:nil
                  preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"OK", nil)
                  style:UIAlertActionStyleCancel
                handler:nil];
    [alert addAction:okAction];
    [self.navigationController presentViewController:alert animated:YES completion:nil];
}

- (void)paymentInputProcessorDidFinishProcessingFile:(DWPaymentProcessor *)processor {
    // NOP
}

// Progress HUD

- (void)paymentProcessor:(DWPaymentProcessor *)processor
    showProgressHUDWithMessage:(nullable NSString *)message {
    [self.navigationController.view dw_showProgressHUDWithMessage:message];
}

- (void)paymentInputProcessorHideProgressHUD:(DWPaymentProcessor *)processor {
    [self.navigationController.view dw_hideProgressHUD];
}

#pragma mark - DWSendAmountViewControllerDelegate

- (void)sendAmountViewController:(DWSendAmountViewController *)controller
                  didInputAmount:(uint64_t)amount
                 usedInstantSend:(BOOL)usedInstantSend {
    NSParameterAssert(self.paymentProcessor);
    [self.paymentProcessor provideAmount:amount usedInstantSend:usedInstantSend];
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

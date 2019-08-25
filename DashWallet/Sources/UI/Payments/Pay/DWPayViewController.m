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
#import "DWQRScanModel.h"
#import "DWQRScanViewController.h"
#import "DWSendAmountViewController.h"
#import "DWUIKit.h"
#import "UIView+DWHUD.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, DWPayControllerInitialAction) {
    DWPayControllerInitialAction_None,
    DWPayControllerInitialAction_ScanQR,
    DWPayControllerInitialAction_PayToPasteboard,
};

@interface DWPayViewController () <UITableViewDataSource,
                                   DWPayTableViewCellDelegate,
                                   DWPaymentProcessorDelegate,
                                   DWSendAmountViewControllerDelegate,
                                   DWQRScanModelDelegate>

@property (strong, nonatomic) IBOutlet UITableView *tableView;

@property (nonatomic, assign) DWPayControllerInitialAction initialAction;
@property (nonatomic, assign) BOOL initialActionDone;

@property (nonatomic, strong) DWPayModel *model;
@property (nonatomic, strong) DWPaymentProcessor *paymentProcessor;

@end

@implementation DWPayViewController

+ (instancetype)controllerWithModel:(DWPayModel *)payModel {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Pay" bundle:nil];
    DWPayViewController *controller = [storyboard instantiateInitialViewController];
    controller.model = payModel;
    DWPaymentProcessor *paymentProcessor = [[DWPaymentProcessor alloc] init];
    paymentProcessor.delegate = controller;
    controller.paymentProcessor = paymentProcessor;

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

    if (self.initialActionDone == NO && self.initialAction != DWPayControllerInitialAction_None) {
        self.initialActionDone = YES;

        switch (self.initialAction) {
            case DWPayControllerInitialAction_None: {
                break;
            }
            case DWPayControllerInitialAction_ScanQR: {
                [self performScanQRCodeAction];

                break;
            }
            case DWPayControllerInitialAction_PayToPasteboard: {
                [self performPayToPasteboardAction];

                break;
            }
        }
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];

    [self.model stopPasteboardIntervalObserving];
}

- (void)scanQRCode {
    self.initialAction = DWPayControllerInitialAction_ScanQR;
}

- (void)payToPasteboard {
    self.initialAction = DWPayControllerInitialAction_PayToPasteboard;
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
            [self performScanQRCodeAction];

            break;
        }
        case DWPayOptionModelType_Pasteboard: {
            [self performPayToPasteboardAction];

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

#pragma mark - DWPaymentProcessorDelegate

// User Actions

- (void)paymentProcessor:(DWPaymentProcessor *)processor
    requestAmountWithDestination:(NSString *)sendingDestination
                         details:(nullable DSPaymentProtocolDetails *)details {
    DWSendAmountViewController *controller =
        [DWSendAmountViewController sendControllerWithDestination:sendingDestination
                                                   paymentDetails:nil];
    controller.delegate = self;
    const BOOL animated = self.initialAction == DWPayControllerInitialAction_PayToPasteboard ? NO : YES;
    [self.navigationController pushViewController:controller animated:animated];
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

- (void)paymentProcessorHideAmountControllerIfNeeded:(nonnull DWPaymentProcessor *)processor {
    if ([self.navigationController.topViewController isKindOfClass:DWSendAmountViewController.class]) {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)paymentProcessor:(DWPaymentProcessor *)processor
        didFailWithTitle:(nullable NSString *)title
                 message:(nullable NSString *)message {
    [self showAlertWithTitle:title message:message];
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

- (void)paymentProcessor:(DWPaymentProcessor *)processor displayFileProcessResult:(NSString *)result {
    [self showAlertWithTitle:result message:nil];
}

- (void)paymentProcessorDidFinishProcessingFile:(DWPaymentProcessor *)processor {
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

#pragma mark -  DWQRScanModelDelegate

- (void)qrScanModel:(DWQRScanModel *)viewModel didScanPaymentInput:(DWPaymentInput *)paymentInput {
    [self dismissViewControllerAnimated:YES
                             completion:^{
                                 [self.paymentProcessor processPaymentInput:paymentInput];
                             }];
}

- (void)qrScanModel:(DWQRScanModel *)viewModel
     showErrorTitle:(nullable NSString *)title
            message:(nullable NSString *)message {
    [self showAlertWithTitle:title message:message];
}

- (void)qrScanModelDidCancel:(DWQRScanModel *)viewModel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Private

- (void)setupView {
    NSString *cellId = DWPayTableViewCell.dw_reuseIdentifier;
    UINib *nib = [UINib nibWithNibName:cellId bundle:nil];
    NSParameterAssert(nib);
    [self.tableView registerNib:nib forCellReuseIdentifier:cellId];

    self.tableView.tableFooterView = [[UIView alloc] init];
}

- (void)performScanQRCodeAction {
    DWQRScanViewController *controller = [[DWQRScanViewController alloc] init];
    controller.model.delegate = self;
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)performPayToPasteboardAction {
    DWPaymentInput *paymentInput = self.model.pasteboardPaymentInput;
    NSParameterAssert(paymentInput);
    if (!paymentInput) {
        return;
    }

    [self.paymentProcessor processPaymentInput:paymentInput];
}

- (void)showAlertWithTitle:(NSString *_Nullable)title message:(NSString *_Nullable)message {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:title
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"OK", nil)
                  style:UIAlertActionStyleCancel
                handler:nil];
    [alert addAction:okAction];
    [self.navigationController presentViewController:alert animated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END

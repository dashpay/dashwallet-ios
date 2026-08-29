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

#import "DWBasePayViewController.h"

#import "DWPayModelProtocol.h"
#import "DWPaymentInputBuilder.h"
#import "DWPaymentProcessor.h"
#import "DWUIKit.h"
#import "UIView+DWHUD.h"
#import "UIViewController+DWEmbedding.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWBasePayViewController () <SuccessTxDetailViewControllerDelegate,
                                       PaymentControllerDelegate,
                                       PaymentControllerPresentationContextProviding>

@property (nonatomic, strong) PaymentController *paymentController;

@end

@implementation DWBasePayViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    NSParameterAssert(self.payModel);

    self.paymentController = [[PaymentController alloc] init];
    _paymentController.delegate = self;
    _paymentController.locksBalance = self.locksBalance;
    _paymentController.presentationContextProvider = self;
}


- (BOOL)allowsScannerCrossContextRouting {
    return YES;
}

- (void)performScanQRCodeAction {
    if ([self.presentedViewController isKindOfClass:DWQRScannerController.class]) {
        return;
    }

    NSAssert(self.presentedViewController == nil, @"Attempt to present on VC which is already presenting %@",
             self.presentedViewController);

    DWQRScannerController *controller =
        [DWQRScannerController paymentScannerWithAllowsCrossContextRouting:self.allowsScannerCrossContextRouting];
    __weak typeof(self) weakSelf = self;
    controller.onPaymentInput = ^(DWPaymentInput *paymentInput) {
        [weakSelf didScanPaymentInput:paymentInput];
    };
    controller.onCancel = ^{
        [weakSelf dismissViewControllerAnimated:YES completion:nil];
    };
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)performPayToPasteboardAction {
    DWPaymentInput *paymentInput = self.payModel.pasteboardPaymentInput;
    NSParameterAssert(paymentInput);
    if (!paymentInput) {
        return;
    }

    [self processPaymentInput:paymentInput];
}

- (void)performNFCReadingAction {
    __weak typeof(self) weakSelf = self;
    [self.payModel performNFCReadingWithCompletion:^(DWPaymentInput *_Nonnull paymentInput) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        [strongSelf processPaymentInput:paymentInput];
    }];
}

- (void)performPayToURL:(NSURL *)url {
    DWPaymentInput *paymentInput = [self.payModel paymentInputWithURL:url];

    [self processPaymentInput:paymentInput];
}

- (void)processPaymentInput:(DWPaymentInput *)input {
    [self.paymentController performPaymentWith:input];
}

#pragma mark - DWTxDetailFullscreenViewControllerDelegate

- (void)txDetailViewControllerDidFinishWithController:(SuccessTxDetailViewController *)controller {
    // Nothing to do — the success screen dismisses itself; the legacy pay-to-contact
    // follow-up that lived here is gone with the contact plumbing (Row #18).
}

#pragma mark - Scanner completion

- (void)didScanPaymentInput:(DWPaymentInput *)paymentInput {
    self.view.userInteractionEnabled = NO;
    [self dismissViewControllerAnimated:YES
                             completion:^{
                                 // A bech32m Platform/Shielded destination can't ride the classic
                                 // L1 payment processor — open the Send screen prefilled instead
                                 // (its route model handles all destination forms). Base58 Core
                                 // scans keep the legacy processor path unchanged.
                                 DWParsedPaymentURI *parsed = paymentInput.parsedURI;
                                 if (parsed.requiresSendScreenRouting && parsed.address != nil) {
                                     [self routeScannedBech32Address:parsed];
                                 }
                                 else {
                                     [self processPaymentInput:paymentInput];
                                 }

                                 self.view.userInteractionEnabled = YES;
                             }];
}

/// Present the Send screen prefilled with a scanned bech32m destination —
/// same presentation chrome as the payments landing (hidden-bar navigation
/// controller, full screen; the screen draws its own X/title header).
- (void)routeScannedBech32Address:(DWParsedPaymentURI *)parsed {
    DWSendScreenViewController *controller = [[DWSendScreenViewController alloc] init];
    [controller prefillWithAddress:parsed.address amountDuffs:parsed.amount];
    DWNavigationController *navigationController =
        [[DWNavigationController alloc] initWithRootViewController:controller];
    navigationController.navigationBarHidden = YES;
    navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navigationController animated:YES completion:nil];
}

#pragma mark - PaymentControllerDelegate

- (void)paymentControllerDidCancelTransaction:(PaymentController *_Nonnull)controller {
}

- (void)paymentControllerDidFailTransaction:(PaymentController *)controller {
}

- (void)paymentControllerDidFinishTransaction:(PaymentController *_Nonnull)controller txidWire:(NSData *_Nonnull)txidWire {
    void (^presentSuccess)(void) = ^{
        DWTxDetailModel *model = [[DWTxDetailModel alloc] initWithTxidWire:txidWire];
        SuccessTxDetailViewController *vc = [[SuccessTxDetailViewController alloc] initWithModel:model];
        vc.delegate = self;
        [self presentViewController:vc
                           animated:YES
                         completion:nil];
    };

    if (self.presentedViewController) {
        [self dismissViewControllerAnimated:YES completion:presentSuccess];
    }
    else {
        // Nothing is presented from self (PaymentController already dismissed
        // the confirm sheet). A bare `dismissViewControllerAnimated:` here
        // forwards to the presenting controller and tears down THIS
        // controller's own modal stack — on the modally-presented Send screen
        // that detached `self` and UIKit refused the follow-up present
        // ("whose view is not in the window hierarchy"), so the success
        // screen never appeared. Present directly instead.
        presentSuccess();
    }
}

- (UIViewController *_Nonnull)presentationAnchorForPaymentController:(PaymentController *_Nonnull)controller {
    return self;
}


@end

NS_ASSUME_NONNULL_END

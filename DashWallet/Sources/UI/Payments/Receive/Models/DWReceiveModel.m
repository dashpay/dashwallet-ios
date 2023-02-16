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

#import "DWReceiveModel.h"

#import <UIKit/UIPasteboard.h>

#import "DWAppGroupOptions.h"
#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "UIImage+Utils.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWReceiveModel ()

@property (nullable, nonatomic, strong) UIImage *qrCodeImage;
@property (nullable, nonatomic, copy) NSString *paymentAddress;
@property (nullable, nonatomic, strong) DSPaymentRequest *paymentRequest;
@property (nonatomic, strong) dispatch_queue_t updateQueue;

@end

@implementation DWReceiveModel

- (instancetype)initWithAmount:(uint64_t)amount {
    self = [super initWithAmount:amount];
    if (self) {
        _updateQueue = dispatch_queue_create("org.dash.wallet.DWReceiveModel.queue", DISPATCH_QUEUE_SERIAL);

        [self updateReceivingInfo];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(transactionReceivedNotification)
                                                     name:DSTransactionManagerTransactionReceivedNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    DSLog(@"☠️ %@", NSStringFromClass(self.class));
}

- (NSString *)paymentAddressOrRequestToShare {
    if (self.amount > 0) {
        return self.paymentRequest.string;
    }
    else {
        return self.paymentAddress;
    }
}

- (void)copyAddressToPasteboard {
    NSString *paymentAddress = [self paymentAddressOrRequestToShare];
    NSParameterAssert(paymentAddress);
    if (!paymentAddress) {
        return;
    }

    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = paymentAddress;
}

- (void)copyQRImageToPasteboard {
    UIImage *qrImage = self.qrCodeImage;
    NSParameterAssert(qrImage);
    if (!qrImage) {
        return;
    }

    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.image = qrImage;
}

- (nullable NSString *)requestAmountReceivedInfoIfReceived {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSChainManager *chainManager = [DWEnvironment sharedInstance].currentChainManager;
    DSPaymentRequest *request = self.paymentRequest;
    uint64_t total = 0;
    const uint64_t fuzz = [CurrencyExchangerObjcWrapper amountForLocalCurrency:[CurrencyExchangerObjcWrapper localCurrencyNumberForDashAmount:1].decimalValue] * 2;

    if (![wallet addressIsUsed:request.paymentAddress]) {
        return nil;
    }

    for (DSTransaction *tx in wallet.allTransactions) {
        if ([tx.outputAddresses containsObject:request.paymentAddress]) {
            continue;
        }
        if (tx.blockHeight == TX_UNCONFIRMED &&
            [chainManager.transactionManager relayCountForTransaction:tx.txHash] < PEER_MAX_CONNECTIONS) {
            continue;
        }

        total += [wallet amountReceivedFromTransaction:tx];

        if (total + fuzz >= request.amount) {
            DSLog(@"DWReceiveModel: Received %@", @(total));

            // TODO: Fix me. Using `self.amount` here is a workaround and we should use `total` instead.
            // (`total` is not calculated properly for very small amounts like 0.000257)

            NSString *info = [NSString stringWithFormat:NSLocalizedString(@"Received %@ (%@)", nil),
                                                        [CurrencyExchangerObjcWrapper stringForDashAmount:self.amount],
                                                        [CurrencyExchangerObjcWrapper localCurrencyStringForDashAmount:self.amount]];

            return info;
        }
    }

    return nil;
}


#pragma mark - Notifications

- (void)transactionReceivedNotification {
    [self updateReceivingInfo];
}

#pragma mark - Private

- (void)updateReceivingInfo {
    dispatch_async(self.updateQueue, ^{
        DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
        if (!account) {
            // wallet has been wiped

            return;
        }
        NSString *paymentAddress = account.receiveAddress;

        DSChain *chain = [DWEnvironment sharedInstance].currentChain;
        DWAppGroupOptions *appGroupOptions = [DWAppGroupOptions sharedInstance];
        DSPaymentRequest *paymentRequest = [DSPaymentRequest requestWithString:paymentAddress onChain:chain];

        const uint64_t amount = self.amount;
        const BOOL hasAmount = amount > 0;
        if (hasAmount) {
            paymentRequest.amount = amount;

            NSNumber *number = [CurrencyExchangerObjcWrapper localCurrencyNumberForDashAmount:amount];
            if (number) {
                paymentRequest.requestedFiatCurrencyAmount = number.floatValue;
            }
            paymentRequest.requestedFiatCurrencyCode = CurrencyExchangerObjcWrapper.localCurrencyCode;
        }

        paymentRequest.dashpayUsername = [DWGlobalOptions sharedInstance].dashpayUsername;

        UIImage *rawQRImage = nil;
        if (!hasAmount && [paymentRequest.data isEqual:appGroupOptions.receiveRequestData]) {
            NSData *qrImageData = appGroupOptions.receiveQRImageData;
            if (qrImageData) {
                rawQRImage = [UIImage imageWithData:qrImageData];
            }
        }

        if (!rawQRImage && paymentRequest.data) {
            // always black
            rawQRImage = [UIImage dw_imageWithQRCodeData:paymentRequest.data color:[CIColor blackColor]];
        }

        UIImage *qrCodeImage = [self qrCodeImageWithRawQRImage:rawQRImage hasAmount:hasAmount];

        NSData *rawQRImageData = UIImagePNGRepresentation(rawQRImage);
        if (paymentRequest && paymentRequest.isValidAsNonDashpayPaymentRequest && rawQRImageData) {
            if (!hasAmount) {
                appGroupOptions.receiveQRImageData = rawQRImageData;
                appGroupOptions.receiveAddress = paymentAddress;
                appGroupOptions.receiveRequestData = paymentRequest.data;
            }
        }
        else {
            if (!hasAmount) {
                appGroupOptions.receiveQRImageData = nil;
                appGroupOptions.receiveAddress = nil;
                appGroupOptions.receiveRequestData = nil;
            }

            paymentAddress = nil;
            qrCodeImage = nil;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.paymentRequest = paymentRequest;
            self.qrCodeImage = qrCodeImage;
            self.paymentAddress = paymentAddress;
        });
    });
}

@end

NS_ASSUME_NONNULL_END

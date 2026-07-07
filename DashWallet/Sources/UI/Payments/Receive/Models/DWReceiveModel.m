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
#if DASHPAY
@property (nullable, nonatomic, copy) NSString *username;
#endif
@property (nullable, nonatomic, strong) DWPaymentURIBuilder *paymentRequest;
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

        // Re-fetch the receive address as SwiftDashSDK's SPV catches up.
        // Rust's persister writes PersistentTransaction rows on every Core
        // SPV / BLAST batch and SwiftData posts NSManagedObjectContextDidSave
        // under the hood; observing that signal lets the displayed address
        // advance to the next-unused BIP44 index once the used-set updates.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(transactionReceivedNotification)
                                                     name:NSManagedObjectContextDidSaveNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    DWLog(@"☠️ %@", NSStringFromClass(self.class));
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

#if DASHPAY
- (void)copyUsernameToPasteboard {
    NSString *username = self.paymentRequest.dashpayUsername;

    if (!username) {
        return;
    }

    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = username;
}
#endif

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
    DWPaymentURIBuilder *request = self.paymentRequest;
    const uint64_t fuzz = [CurrencyExchangerObjcWrapper amountForLocalCurrency:[CurrencyExchangerObjcWrapper localCurrencyNumberForDashAmount:1].decimalValue] * 2;

    if (![DWSwiftDashSDKReceiveAddressReader isAddressUsed:request.address]) {
        return nil;
    }

    const uint64_t total = [DWSwiftDashSDKReceiveAddressReader receivedTotalExcludingAddress:request.address];

    if (total + fuzz >= request.amount) {
        DWLog(@"DWReceiveModel: Received %@", @(total));

        // TODO: Fix me. Using `self.amount` here is a workaround and we should use `total` instead.
        // (`total` is not calculated properly for very small amounts like 0.000257)

        NSString *info = [NSString stringWithFormat:NSLocalizedString(@"Received %@ (%@)", nil),
                                                    [CurrencyExchangerObjcWrapper stringForDashAmount:self.amount],
                                                    [CurrencyExchangerObjcWrapper localCurrencyStringForDashAmount:self.amount]];

        return info;
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
        NSString *paymentAddress = [DWSwiftDashSDKReceiveAddressReader receiveAddress];

        DWAppGroupOptions *appGroupOptions = [DWAppGroupOptions sharedInstance];

        const uint64_t amount = self.amount;
        const BOOL hasAmount = amount > 0;

        NSString *fiatCode = nil;
        float fiatAmount = 0;
        if (hasAmount) {
            NSNumber *number = [CurrencyExchangerObjcWrapper localCurrencyNumberForDashAmount:amount];
            if (number) {
                fiatAmount = number.floatValue;
            }
            fiatCode = CurrencyExchangerObjcWrapper.localCurrencyCode;
        }
        NSString *dashpayUsername = nil;
#if DASHPAY
        dashpayUsername = [DWGlobalOptions sharedInstance].dashpayUsername;
#endif
        DWPaymentURIBuilder *paymentRequest = [[DWPaymentURIBuilder alloc] initWithAddress:paymentAddress
                                                                                    amount:amount
                                                                                     label:nil
                                                                                   message:nil
                                                                                requestURL:nil
                                                                          fiatCurrencyCode:fiatCode
                                                                                fiatAmount:fiatAmount
                                                                           dashpayUsername:dashpayUsername];

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
        const BOOL addressValid = [[DWParsedPaymentURI parsePaymentString:paymentAddress] isAddressValidForCurrentNetwork];
        if (addressValid && rawQRImageData) {
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
#if DASHPAY
            self.username = paymentRequest.dashpayUsername;
#endif
            [self.delegate receivingInfoDidUpdate];
        });
    });
}

@end

NS_ASSUME_NONNULL_END

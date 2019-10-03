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
#import "DevicesCompatibility.h"
#import "UIImage+Utils.h"

NS_ASSUME_NONNULL_BEGIN

static CGSize QRCodeSizeBasic(void) {
    if (IS_IPAD) {
        return CGSizeMake(360.0, 360.0);
    }
    else {
        const CGFloat screenWidth = CGRectGetWidth([UIScreen mainScreen].bounds);
        const CGFloat padding = 38.0;
        const CGFloat side = screenWidth - padding * 2;

        return CGSizeMake(side, side);
    }
}

static CGSize QRCodeSizeRequestAmount(void) {
    if (IS_IPAD) {
        return CGSizeMake(360.0, 360.0);
    }
    else {
        return CGSizeMake(200.0, 200.0);
    }
}

static CGSize HoleSize(BOOL hasAmount) {
    if (IS_IPAD) {
        return CGSizeMake(84.0, 84.0); // 2 + 80(logo size) + 2
    }
    else if (IS_IPHONE_5_OR_LESS) {
        return CGSizeMake(58.0, 58.0);
    }
    else {
        if (hasAmount) {
            return CGSizeMake(58.0, 58.0);
        }
        else {
            return CGSizeMake(84.0, 84.0);
        }
    }
}

static CGSize const LOGO_SMALL_SIZE = {54.0, 54.0};

static BOOL ShouldResizeLogoToSmall(BOOL hasAmount) {
    if (IS_IPAD) {
        return NO;
    }
    if (IS_IPHONE_5_OR_LESS) {
        return YES;
    }
    else {
        return hasAmount;
    }
}

@interface DWReceiveModel ()

@property (nullable, nonatomic, strong) UIImage *qrCodeImage;
@property (nullable, nonatomic, copy) NSString *paymentAddress;
@property (nullable, nonatomic, strong) DSPaymentRequest *paymentRequest;
@property (nonatomic, assign) CGSize qrCodeSize;
@property (nonatomic, assign) CGSize holeSize;

@end

@implementation DWReceiveModel

- (instancetype)init {
    return [self initWithAmount:0];
}

- (instancetype)initWithAmount:(uint64_t)amount {
    self = [super init];
    if (self) {
        _amount = amount;

        DSLogVerbose(@"DWReceiveModel: Requesting %@", @(amount));

        const BOOL hasAmount = amount > 0;
        if (hasAmount) {
            _qrCodeSize = QRCodeSizeRequestAmount();
        }
        else {
            _qrCodeSize = QRCodeSizeBasic();
        }
        _holeSize = HoleSize(hasAmount);

        [self updateReceivingInfo];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(transactionReceivedNotification)
                                                     name:DSTransactionManagerTransactionReceivedNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    DSLogVerbose(@"☠️ %@", NSStringFromClass(self.class));
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
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSChainManager *chainManager = [DWEnvironment sharedInstance].currentChainManager;
    DSPaymentRequest *request = self.paymentRequest;
    uint64_t total = 0;
    const uint64_t fuzz = [priceManager amountForLocalCurrencyString:[priceManager localCurrencyStringForDashAmount:1]] * 2;

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
            DSLogVerbose(@"DWReceiveModel: Received %@", @(total));

            // TODO: Fix me. Using `self.amount` here is a workaround and we should use `total` instead.
            // (`total` is not calculated properly for very small amounts like 0.000257)

            NSString *info = [NSString stringWithFormat:NSLocalizedString(@"received %@ (%@)", nil),
                                                        [priceManager stringForDashAmount:self.amount],
                                                        [priceManager localCurrencyStringForDashAmount:self.amount]];

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
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
        if (!account) {
            // wallet has been wiped

            return;
        }
        NSString *paymentAddress = account.receiveAddress;
        if (self.paymentAddress && [self.paymentAddress isEqualToString:paymentAddress]) {
            return;
        }

        DSChain *chain = [DWEnvironment sharedInstance].currentChain;
        DWAppGroupOptions *appGroupOptions = [DWAppGroupOptions sharedInstance];
        DSPaymentRequest *paymentRequest = [DSPaymentRequest requestWithString:paymentAddress onChain:chain];

        const uint64_t amount = self.amount;
        const BOOL hasAmount = amount > 0;
        if (hasAmount) {
            paymentRequest.amount = amount;

            DSPriceManager *priceManager = [DSPriceManager sharedInstance];
            NSNumber *number = [priceManager localCurrencyNumberForDashAmount:amount];
            if (number) {
                paymentRequest.requestedFiatCurrencyAmount = number.floatValue;
            }
            paymentRequest.requestedFiatCurrencyCode = priceManager.localCurrencyCode;
        }
        self.paymentRequest = paymentRequest;

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

        UIImage *overlayLogo = [UIImage imageNamed:@"dash_logo_qr"];
        NSParameterAssert(overlayLogo);

        if (ShouldResizeLogoToSmall(hasAmount)) {
            overlayLogo = [overlayLogo dw_resize:LOGO_SMALL_SIZE
                        withInterpolationQuality:kCGInterpolationHigh];
        }

        UIImage *resizedImage = [rawQRImage dw_resize:self.qrCodeSize withInterpolationQuality:kCGInterpolationNone];
        resizedImage = [resizedImage dw_imageByCuttingHoleInCenterWithSize:self.holeSize];

        UIImage *qrCodeImage = [resizedImage dw_imageByMergingWithImage:overlayLogo];

        NSData *rawQRImageData = UIImagePNGRepresentation(rawQRImage);
        if (paymentRequest && paymentRequest.isValid && rawQRImageData) {
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
            self.qrCodeImage = qrCodeImage;
            self.paymentAddress = paymentAddress;
        });
    });
}

@end

NS_ASSUME_NONNULL_END

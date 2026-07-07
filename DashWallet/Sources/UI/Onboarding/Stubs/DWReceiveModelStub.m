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

#import "DWReceiveModelStub.h"

#import "UIImage+Utils.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWReceiveModelStub ()

@property (nullable, nonatomic, strong) UIImage *qrCodeImage;
@property (nullable, nonatomic, copy) NSString *paymentAddress;
@property (nullable, nonatomic, strong) DWPaymentURIBuilder *paymentRequest;

@end

@implementation DWReceiveModelStub

- (instancetype)initWithAmount:(uint64_t)amount {
    self = [super initWithAmount:amount];
    if (self) {
        [self updateReceivingInfo];
    }

    return self;
}

- (void)copyAddressToPasteboard {
}

- (void)copyQRImageToPasteboard {
}

- (NSString *)paymentAddressOrRequestToShare {
    if (self.amount > 0) {
        return self.paymentRequest.string;
    }
    else {
        return self.paymentAddress;
    }
}

- (nullable NSString *)requestAmountReceivedInfoIfReceived {
    return nil;
}

- (void)updateReceivingInfo {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *paymentAddress = @"XrUv3aniSvZEKx2VoFe5fTqFfYL5JYFkbg";

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
        DWPaymentURIBuilder *paymentRequest = [[DWPaymentURIBuilder alloc] initWithAddress:paymentAddress
                                                                                    amount:amount
                                                                                     label:nil
                                                                                   message:nil
                                                                                requestURL:nil
                                                                          fiatCurrencyCode:fiatCode
                                                                                fiatAmount:fiatAmount
                                                                           dashpayUsername:nil];
        self.paymentRequest = paymentRequest;

        UIImage *rawQRImage = nil;
        if (!rawQRImage && paymentRequest.data) {
            // always black
            rawQRImage = [UIImage dw_imageWithQRCodeData:paymentRequest.data color:[CIColor blackColor]];
        }

        UIImage *qrCodeImage = [self qrCodeImageWithRawQRImage:rawQRImage hasAmount:hasAmount];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.qrCodeImage = qrCodeImage;
            self.paymentAddress = paymentAddress;
        });
    });
}

@end

NS_ASSUME_NONNULL_END

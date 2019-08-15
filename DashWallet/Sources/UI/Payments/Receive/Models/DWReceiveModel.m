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

#import <DashSync/DashSync.h>
#import <UIKit/UIPasteboard.h>

#import "DWAppGroupOptions.h"
#import "DWEnvironment.h"
#import "DevicesCompatibility.h"
#import "UIImage+Utils.h"

NS_ASSUME_NONNULL_BEGIN

static CGSize QRCodeSize(void) {
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

static CGSize const HOLE_SIZE = {84.0, 84.0}; // 2 + 80(logo size) + 2

@interface DWReceiveModel ()

@property (nullable, nonatomic, strong) UIImage *qrCodeImage;
@property (nullable, nonatomic, copy) NSString *paymentAddress;

@end

@implementation DWReceiveModel

- (instancetype)init {
    self = [super init];
    if (self) {
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

- (CGSize)qrCodeSize {
    return QRCodeSize();
}

- (void)copyAddressToPasteboard {
    NSString *paymentAddress = self.paymentAddress;
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

        UIImage *rawQRImage = nil;
        if ([paymentRequest.data isEqual:appGroupOptions.receiveRequestData]) {
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
        UIImage *resizedImage = [rawQRImage dw_resize:self.qrCodeSize withInterpolationQuality:kCGInterpolationNone];
        resizedImage = [resizedImage dw_imageByCuttingHoleInCenterWithSize:HOLE_SIZE];

        UIImage *qrCodeImage = [resizedImage dw_imageByMergingWithImage:overlayLogo];

        NSData *rawQRImageData = UIImagePNGRepresentation(rawQRImage);
        if (paymentRequest.isValid && rawQRImageData) {
            appGroupOptions.receiveQRImageData = rawQRImageData;
            appGroupOptions.receiveAddress = paymentAddress;
            appGroupOptions.receiveRequestData = paymentRequest.data;
        }
        else {
            appGroupOptions.receiveQRImageData = nil;
            appGroupOptions.receiveAddress = nil;
            appGroupOptions.receiveRequestData = nil;

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

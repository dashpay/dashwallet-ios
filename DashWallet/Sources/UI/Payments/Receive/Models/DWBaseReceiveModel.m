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

#import "DWBaseReceiveModel.h"

#import "DWGlobalOptions.h"
#import "DevicesCompatibility.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

static CGSize QRCodeSizeBasic(void) {
    if (IS_IPAD) {
        return CGSizeMake(360.0, 360.0);
    }
    else if (IS_IPHONE_5_OR_LESS) {
        return CGSizeMake(220.0, 220.0);
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

@interface DWBaseReceiveModel ()

@property (readonly, nonatomic, assign) CGSize logoSize;

@end

@implementation DWBaseReceiveModel

- (instancetype)init {
    return [self initWithAmount:0];
}

- (instancetype)initWithAmount:(uint64_t)amount {
    self = [super init];
    if (self) {
        _amount = amount;

        const BOOL hasAmount = amount > 0;
        if (hasAmount) {
            _qrCodeSize = QRCodeSizeRequestAmount();
        }
        else {
            _qrCodeSize = QRCodeSizeBasic();
        }

        CGFloat logoSize = _qrCodeSize.height * 0.22;
        _logoSize = CGSizeMake(logoSize, logoSize);
    }
    return self;
}

- (UIImage *)qrCodeImageWithRawQRImage:(UIImage *)rawQRImage hasAmount:(BOOL)hasAmount {
    NSString *username = nil;
#if DASHPAY
    username = [DWGlobalOptions sharedInstance].dashpayUsername;
#endif

    UIImage *overlayImage;
    if (username != nil) {
        // TODO: DP handle avatar image
        overlayImage = [DWQRCodeFactory usernameOverlayImageWithUsername:username
                                                                    size:self.logoSize
                                                               hasAmount:self.amount > 0];
    }
    else {
        overlayImage = [UIImage imageNamed:@"dash_logo_qr"];
        NSParameterAssert(overlayImage);
    }

    return [DWQRCodeFactory compositedQRImageWithRawQRImage:rawQRImage
                                                 targetSize:self.qrCodeSize
                                                   holeSize:self.logoSize
                                                    overlay:overlayImage
                                                overlaySize:self.logoSize];
}

@end

NS_ASSUME_NONNULL_END

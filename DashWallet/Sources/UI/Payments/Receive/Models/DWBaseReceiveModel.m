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

@interface DWBaseReceiveModel ()

@property (readonly, nonatomic, assign) CGSize holeSize;

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
        _holeSize = HoleSize(hasAmount);
    }
    return self;
}

- (UIImage *)qrCodeImageWithRawQRImage:(UIImage *)rawQRImage hasAmount:(BOOL)hasAmount {
    UIImage *overlayLogo = [UIImage imageNamed:@"dash_logo_qr"];
    NSParameterAssert(overlayLogo);

    if (ShouldResizeLogoToSmall(hasAmount)) {
        overlayLogo = [overlayLogo dw_resize:LOGO_SMALL_SIZE
                    withInterpolationQuality:kCGInterpolationHigh];
    }

    UIImage *resizedImage = [rawQRImage dw_resize:self.qrCodeSize withInterpolationQuality:kCGInterpolationNone];
    resizedImage = [resizedImage dw_imageByCuttingHoleInCenterWithSize:self.holeSize];

    UIImage *qrCodeImage = [resizedImage dw_imageByMergingWithImage:overlayLogo];

    return qrCodeImage;
}

@end

NS_ASSUME_NONNULL_END

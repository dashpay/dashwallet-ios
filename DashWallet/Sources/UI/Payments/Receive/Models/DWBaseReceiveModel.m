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
#import "UIColor+DWDashPay.h"
#import "UIColor+DWStyle.h"
#import "UIFont+DWFont.h"
#import "UIImage+Utils.h"

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

static CGSize HoleSize(BOOL hasAmount) {
    if (IS_IPAD) {
        return CGSizeMake(84.0, 84.0); // 2 + 80(logo size) + 2
    }
    else if (IS_IPHONE_5_OR_LESS) {
        return CGSizeMake(48.0, 48.0);
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
    UIImage *overlayImage = [UIImage imageNamed:@"dash_logo_qr"];
    NSParameterAssert(overlayImage);

    CGSize size = overlayImage.size;
    NSString *username = [DWGlobalOptions sharedInstance].dashpayUsername;
    const BOOL shouldDrawUser = username != nil;

    if (ShouldResizeLogoToSmall(hasAmount)) {
        if (shouldDrawUser) {
            size = LOGO_SMALL_SIZE;
        }
        else {
            overlayImage = [overlayImage dw_resize:LOGO_SMALL_SIZE
                          withInterpolationQuality:kCGInterpolationHigh];
        }
    }

    if (shouldDrawUser) {
        // TODO: DP handle avatar image

        const BOOL hasAmount = self.amount > 0;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
        overlayImage = [renderer imageWithActions:^(UIGraphicsImageRendererContext *_Nonnull rendererContext) {
            CGContextRef context = rendererContext.CGContext;
            CGRect rect = CGRectMake(0, 0, size.width, size.height);

            UIColor *usernameBgColor = [UIColor dw_colorWithUsername:username];
            CGFloat red, green, blue, alpha;
            [usernameBgColor getRed:&red green:&green blue:&blue alpha:&alpha];

            CGContextSetRGBFillColor(context, red, green, blue, alpha);
            CGContextSetRGBStrokeColor(context, 62.0 / 255.0, 141.0 / 255.0, 221.0 / 255.0, 1.0); // Dash-blue color

            // Draw stroke as x2 and clip the rest

            const CGFloat strokeWidth = hasAmount ? 4 : 5;
            CGContextSetLineWidth(context, strokeWidth * 2);

            CGRect pathRect = CGRectMake(strokeWidth, strokeWidth,
                                         rect.size.width - strokeWidth * 2, rect.size.height - strokeWidth * 2);
            CGPathRef path = [UIBezierPath bezierPathWithOvalInRect:rect].CGPath;
            CGContextAddPath(context, path);
            CGContextClip(context);
            CGContextAddPath(context, path);
            CGContextDrawPath(context, kCGPathEOFillStroke);

            UIFont *font = nil;
            if (hasAmount) {
                font = [UIFont dw_regularFontOfSize:20];
            }
            else {
                font = [UIFont dw_regularFontOfSize:30];
            }
            UIColor *textColor = [UIColor dw_lightTitleColor];
            NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
            style.alignment = NSTextAlignmentCenter;
            style.minimumLineHeight = rect.size.height / 2.0 + font.lineHeight / 2.0;
            NSAttributedString *string = [[NSAttributedString alloc] initWithString:[[username substringToIndex:1] uppercaseString]
                                                                         attributes:@{NSFontAttributeName : font, NSForegroundColorAttributeName : textColor, NSParagraphStyleAttributeName : style}];
            [string drawInRect:rect];
        }];
    }

    UIImage *resizedImage = [rawQRImage dw_resize:self.qrCodeSize withInterpolationQuality:kCGInterpolationNone];
    resizedImage = [resizedImage dw_imageByCuttingHoleInCenterWithSize:self.holeSize];

    UIImage *qrCodeImage = [resizedImage dw_imageByMergingWithImage:overlayImage];

    return qrCodeImage;
}

@end

NS_ASSUME_NONNULL_END

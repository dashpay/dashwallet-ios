//
//  DWQRScanView.m
//  dashwallet
//
//  Created by Andrew Podkovyrin on 21/12/2017.
//  Copyright © 2017 Aaron Voisine. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import <AVFoundation/AVFoundation.h>

#import "DWQRScanModel.h"
#import "DWQRScanView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWQRScanView ()

@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) CAShapeLayer *qrCodeLayer;
@property (nonatomic, strong) CATextLayer *qrCodeTextLayer;

@end

@implementation DWQRScanView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];

        AVCaptureVideoPreviewLayer *previewLayer = [AVCaptureVideoPreviewLayer layer];
        previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [self.layer addSublayer:previewLayer];
        _previewLayer = previewLayer;

        UIImageView *frameImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"qr_frame"]];
        frameImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:frameImageView];

        NSArray *toolbarItems;
        UIBarButtonItem *cancelButton =
            [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"icon_qr_cancel"]
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(cancelButtonAction:)];
        if (DWQRScanModel.isTorchAvailable) {
            UIBarButtonItem *flexItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                                      target:nil
                                                                                      action:nil];
            UIBarButtonItem *torchButton =
                [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"icon_qr_flash"]
                                                 style:UIBarButtonItemStylePlain
                                                target:self
                                                action:@selector(torchButtonAction:)];
            toolbarItems = @[ cancelButton, flexItem, torchButton ];
        }
        else {
            toolbarItems = @[ cancelButton ];
        }

        UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectZero];
        toolbar.translatesAutoresizingMaskIntoConstraints = NO;
        toolbar.items = toolbarItems;
        toolbar.barStyle = UIBarStyleBlack;
        toolbar.translucent = YES;
        toolbar.tintColor = [UIColor whiteColor];
        [toolbar setBackgroundImage:[UIImage new]
                 forToolbarPosition:UIBarPositionAny
                         barMetrics:UIBarMetricsDefault];
        [toolbar setShadowImage:[UIImage new] forToolbarPosition:UIBarPositionAny];
        [self addSubview:toolbar];

        // Layout

        [NSLayoutConstraint activateConstraints:@[
            [frameImageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [frameImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [toolbar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [toolbar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [toolbar.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor],
        ]];

        // KVO

        [self mvvm_observe:DW_KEYPATH(self, model.qrCodeObject)
                      with:^(typeof(self) self, id value) {
                          [self handleQRCodeObject:self.model.qrCodeObject];
                      }];

        [self mvvm_observe:DW_KEYPATH(self, model.qrCodeObject.type)
                      with:^(typeof(self) self, NSNumber *value) {
                          [self updateQRCodeLayer:self.qrCodeLayer forObject:self.model.qrCodeObject];
                      }];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.previewLayer.frame = self.bounds;
}

- (void)connectCaptureSession {
    NSParameterAssert(self.model);

    self.previewLayer.session = self.model.captureSession;
}

- (void)disconnectCaptureSession {
    self.previewLayer.session = nil;
}

#pragma mark Actions

- (void)cancelButtonAction:(id)sender {
    [self.model cancel];
}

- (void)torchButtonAction:(id)sender {
    [self.model switchTorch];
}

#pragma mark Private

- (void)handleQRCodeObject:(QRCodeObject *)qrCodeObject {
    [self.qrCodeLayer removeFromSuperlayer];

    if (!qrCodeObject) {
        return;
    }

    AVMetadataMachineReadableCodeObject *transformedObject =
        (AVMetadataMachineReadableCodeObject *)[self.previewLayer
            transformedMetadataObjectForMetadataObject:qrCodeObject.metadataObject];
    CGMutablePathRef path = CGPathCreateMutable();
    if (transformedObject.corners.count > 0) {
        for (NSDictionary *pointDictionary in transformedObject.corners) {
            CGPoint point;
            CGPointMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)pointDictionary, &point);

            if (pointDictionary == transformedObject.corners.firstObject) {
                CGPathMoveToPoint(path, NULL, point.x, point.y);
            }

            CGPathAddLineToPoint(path, NULL, point.x, point.y);
        }

        CGPathCloseSubpath(path);
    }

    CAShapeLayer *qrCodeLayer = [CAShapeLayer layer];
    qrCodeLayer.path = path;
    qrCodeLayer.lineJoin = kCALineJoinRound;
    qrCodeLayer.lineWidth = 4.0;

    [self updateQRCodeLayer:qrCodeLayer forObject:qrCodeObject];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self.previewLayer addSublayer:qrCodeLayer];
    [CATransaction commit];
    self.qrCodeLayer = qrCodeLayer;
}

- (void)updateQRCodeLayer:(CAShapeLayer *)layer forObject:(QRCodeObject *)qrCodeObject {
    UIColor *color = nil;
    switch (qrCodeObject.type) {
        case QRCodeObjectTypeProcessing:
        case QRCodeObjectTypeValid:
            color = [UIColor dw_greenColor];
            break;
        case QRCodeObjectTypeInvalid:
            color = [UIColor dw_redColor];
            break;
    }

    layer.strokeColor = [color colorWithAlphaComponent:0.7].CGColor;
    layer.fillColor = [color colorWithAlphaComponent:0.3].CGColor;

    [self.qrCodeTextLayer removeFromSuperlayer];
    if (!qrCodeObject.errorMessage) {
        return;
    }

    CGRect boundingBox = CGPathGetBoundingBox(layer.path);
    UIFont *font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
    NSDictionary *attributes = @{
        NSFontAttributeName : font,
        NSForegroundColorAttributeName : [UIColor dw_lightTitleColor],
    };
    CGRect textRect = [qrCodeObject.errorMessage boundingRectWithSize:boundingBox.size
                                                              options:NSStringDrawingUsesLineFragmentOrigin
                                                           attributes:attributes
                                                              context:nil];
    CATextLayer *textLayer = [CATextLayer layer];
    textLayer.alignmentMode = kCAAlignmentCenter;
    textLayer.frame = textRect;
    textLayer.contentsScale = [UIScreen mainScreen].scale;
    textLayer.font = (__bridge CFTypeRef _Nullable)(font.fontName);
    textLayer.position = CGPointMake(CGRectGetMidX(boundingBox), CGRectGetMidY(boundingBox));
    textLayer.string = [[NSAttributedString alloc] initWithString:qrCodeObject.errorMessage
                                                       attributes:attributes];
    textLayer.wrapped = YES;
    [layer addSublayer:textLayer];
    self.qrCodeTextLayer = textLayer;
}

@end

NS_ASSUME_NONNULL_END

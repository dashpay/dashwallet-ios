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

#import "DWCaptureSessionFrameDelegate.h"
#import "DWQRScanModel.h"
#import "DWQRScanStatusView.h"
#import "DWQRScanView.h"
#import "DWUIKit.h"
#import <DashSync/DSLogger.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWQRScanView () <DWCaptureSessionFrameDelegate>

@property (readonly, nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (readonly, nonatomic, strong) AVSampleBufferDisplayLayer *sampleBufferDisplayLayer;

@property (readonly, nonatomic, strong) DWQRScanStatusView *statusView;
@property (nullable, nonatomic, strong) CAShapeLayer *qrCodeLayer;

@property (atomic, assign) BOOL pauseAcceptingSampleBuffers;

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

        AVSampleBufferDisplayLayer *sampleBufferDisplayLayer = [AVSampleBufferDisplayLayer layer];
        sampleBufferDisplayLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        sampleBufferDisplayLayer.opacity = 0.95;
        [self.layer addSublayer:sampleBufferDisplayLayer];
        _sampleBufferDisplayLayer = sampleBufferDisplayLayer;

        UIImageView *frameImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"qr_frame"]];
        frameImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:frameImageView];

        DWQRScanStatusView *statusView = [[DWQRScanStatusView alloc] initWithFrame:CGRectZero];
        statusView.translatesAutoresizingMaskIntoConstraints = NO;
        statusView.layer.cornerRadius = 8.0;
        statusView.layer.masksToBounds = YES;
        [self addSubview:statusView];
        _statusView = statusView;

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

        [frameImageView setContentHuggingPriority:UILayoutPriorityRequired
                                          forAxis:UILayoutConstraintAxisVertical];
        [frameImageView setContentCompressionResistancePriority:UILayoutPriorityRequired - 1
                                                        forAxis:UILayoutConstraintAxisVertical];

        [statusView setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                    forAxis:UILayoutConstraintAxisVertical];

        UILayoutGuide *guide = self.layoutMarginsGuide;

        [NSLayoutConstraint activateConstraints:@[
            [frameImageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [frameImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [statusView.topAnchor constraintEqualToAnchor:frameImageView.bottomAnchor
                                                 constant:16.0],
            [statusView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [guide.trailingAnchor constraintEqualToAnchor:statusView.trailingAnchor],

            [toolbar.topAnchor constraintEqualToAnchor:statusView.bottomAnchor
                                              constant:16.0],
            [toolbar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [toolbar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [toolbar.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor],
            [toolbar.heightAnchor constraintEqualToConstant:44.0],
        ]];

        // KVO

        [self mvvm_observe:DW_KEYPATH(self, model.qrCodeObject)
                      with:^(typeof(self) self, id value) {
                          [self handleQRCodeObject:self.model.qrCodeObject];
                      }];

        [self mvvm_observe:DW_KEYPATH(self, model.qrCodeObject.type)
                      with:^(typeof(self) self, NSNumber *value) {
                          [self handleQRCodeObject:self.model.qrCodeObject];
                      }];
    }
    return self;
}

- (void)setModel:(DWQRScanModel *)model {
    _model = model;
    _model.frameDelegate = self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.previewLayer.frame = self.bounds;
    self.sampleBufferDisplayLayer.frame = self.bounds;
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

#pragma mark DWCaptureSessionFrameDelegate

- (void)didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!sampleBuffer) {
        return;
    }

    if (self.pauseAcceptingSampleBuffers) {
        return;
    }

    if (self.sampleBufferDisplayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
        DSLogError(@"Failed to display frame: %@", self.sampleBufferDisplayLayer.error);
        [self.sampleBufferDisplayLayer flush];
    }

    [self.sampleBufferDisplayLayer enqueueSampleBuffer:sampleBuffer];
}

#pragma mark Private

- (void)handleQRCodeObject:(QRCodeObject *)qrCodeObject {
    if (qrCodeObject) {
        self.pauseAcceptingSampleBuffers = YES;
    }
    else {
        self.pauseAcceptingSampleBuffers = NO;
    }

    [self updateQRCodeLayerWithObject:qrCodeObject];
    [self updateStatusViewWithObject:qrCodeObject];
}

- (void)updateQRCodeLayerWithObject:(QRCodeObject *)qrCodeObject {
    if (!qrCodeObject) {
        [self.qrCodeLayer removeFromSuperlayer];
        self.qrCodeLayer = nil;

        return;
    }

    if (!self.qrCodeLayer) {
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

        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [self.sampleBufferDisplayLayer addSublayer:qrCodeLayer];
        [CATransaction commit];
        self.qrCodeLayer = qrCodeLayer;
    }

    UIColor *color = [self qrCodeLayerColorForType:qrCodeObject.type];
    UIColor *strokeColor = [color colorWithAlphaComponent:0.7];
    UIColor *fillColor = [color colorWithAlphaComponent:0.3];
    self.qrCodeLayer.strokeColor = strokeColor.CGColor;
    self.qrCodeLayer.fillColor = fillColor.CGColor;
}

- (void)updateStatusViewWithObject:(QRCodeObject *)qrCodeObject {
    BOOL hidden = NO;
    DWQRScanStatus status = DWQRScanStatus_None;
    switch (qrCodeObject.type) {
        case QRCodeObjectTypeProcessing:
        case QRCodeObjectTypeValid: {
            hidden = YES;

            break;
        }
        case QRCodeObjectTypeValidPaymentRequest: {
            status = DWQRScanStatus_Connecting;

            break;
        }
        case QRCodeObjectTypePaymentRequestFailed: {
            status = DWQRScanStatus_UnableToConnect;

            break;
        }
        case QRCodeObjectTypeInvalid: {
            status = DWQRScanStatus_InvalidQR;

            break;
        }
    }

    self.statusView.hidden = hidden;
    [self.statusView updateStatus:status errorMessage:qrCodeObject.errorMessage];
}

- (UIColor *)qrCodeLayerColorForType:(QRCodeObjectType)type {
    switch (type) {
        case QRCodeObjectTypeProcessing:
        case QRCodeObjectTypeValid:
        case QRCodeObjectTypeValidPaymentRequest:
            return [UIColor dw_greenColor];
        case QRCodeObjectTypePaymentRequestFailed:
        case QRCodeObjectTypeInvalid:
            return [UIColor dw_redColor];
    }
}

@end

NS_ASSUME_NONNULL_END

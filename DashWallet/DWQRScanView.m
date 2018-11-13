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

#import "DWQRScanViewModel.h"

#import "DWQRScanView.h"

static void *DWQRScanViewContext = &DWQRScanViewContext;
static NSString *const kQRCodeObjectKeyPath = @"viewModel.qrCodeObject";
static NSString *const kQRCodeObjectTypeKeyPath = @"viewModel.qrCodeObject.type";

@interface DWQRScanView ()

@property (weak, nonatomic) AVCaptureVideoPreviewLayer *previewLayer;
@property (weak, nonatomic) CAShapeLayer *qrCodeLayer;
@property (weak, nonatomic) CATextLayer *qrCodeTextLayer;

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
        
        UIView *overlayView = [[UIView alloc] initWithFrame:CGRectZero];
        overlayView.translatesAutoresizingMaskIntoConstraints = NO;
        overlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.25];
        [self addSubview:overlayView];

        NSArray *toolbarItems;
        UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                                                      target:self
                                                                                      action:@selector(cancelButtonAction:)];
        if (DWQRScanViewModel.isTorchAvailable) {
            UIBarButtonItem *flexItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                                      target:nil
                                                                                      action:nil];
            UIBarButtonItem *torchButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"flash"]
                                                                            style:UIBarButtonItemStylePlain
                                                                           target:self
                                                                           action:@selector(torchButtonAction:)];
            toolbarItems = @[cancelButton, flexItem, torchButton];
        }
        else {
            toolbarItems = @[cancelButton];
        }

        UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectZero];
        toolbar.translatesAutoresizingMaskIntoConstraints = NO;
        toolbar.items = toolbarItems;
        toolbar.barStyle = UIBarStyleBlack;
        toolbar.translucent = YES;
        toolbar.tintColor = [UIColor whiteColor];
        [toolbar setBackgroundImage:[UIImage new] forToolbarPosition:UIBarPositionAny barMetrics:UIBarMetricsDefault];
        [toolbar setShadowImage:[UIImage new] forToolbarPosition:UIBarPositionAny];
        [self addSubview:toolbar];
        
        // Layout
        
        [overlayView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor].active = YES;
        [overlayView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor].active = YES;
        [overlayView.topAnchor constraintEqualToAnchor:toolbar.topAnchor].active = YES;
        [overlayView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor].active = YES;
        
        [toolbar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor].active = YES;
        [toolbar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor].active = YES;
        if (@available(iOS 11.0, *)) {
            [toolbar.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor].active = YES;
        } else {
            [toolbar.bottomAnchor constraintEqualToAnchor:self.bottomAnchor].active = YES;
        }
        
        // KVO
        
        NSKeyValueObservingOptions kvoOptions = (NSKeyValueObservingOptionInitial |
                                                 NSKeyValueObservingOptionNew |
                                                 NSKeyValueObservingOptionOld);
        [self addObserver:self forKeyPath:kQRCodeObjectKeyPath options:kvoOptions context:DWQRScanViewContext];
        [self addObserver:self forKeyPath:kQRCodeObjectTypeKeyPath options:kvoOptions context:DWQRScanViewContext];
    }
    return self;
}

- (void)dealloc {
    [self removeObserver:self forKeyPath:kQRCodeObjectKeyPath context:DWQRScanViewContext];
    [self removeObserver:self forKeyPath:kQRCodeObjectTypeKeyPath context:DWQRScanViewContext];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    self.previewLayer.frame = self.bounds;
}

- (void)setViewModel:(DWQRScanViewModel *)viewModel {
    _viewModel = viewModel;
    
    NSAssert([NSThread isMainThread], @"Current thread is other than main");
    self.previewLayer.session = _viewModel.captureSession;
}

#pragma mark Actions

- (void)cancelButtonAction:(id)sender {
    [self.viewModel cancel];
}

- (void)torchButtonAction:(id)sender {
    [self.viewModel switchTorch];
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
            color = [UIColor yellowColor];
            break;
        case QRCodeObjectTypeValid:
            color = [UIColor greenColor];
            break;
        case QRCodeObjectTypeInvalid:
            color = [UIColor redColor];
            break;
    }
    
    layer.strokeColor = [color colorWithAlphaComponent:0.7].CGColor;
    layer.fillColor = [color colorWithAlphaComponent:0.3].CGColor;
    
    [self.qrCodeTextLayer removeFromSuperlayer];
    if (!qrCodeObject.errorMessage) {
        return;
    }
    
    CGRect boundingBox = CGPathGetBoundingBox(layer.path);
    UIFont *font = [UIFont systemFontOfSize:15.0];
    NSDictionary *attributes = @{
                                 NSFontAttributeName: font,
                                 NSForegroundColorAttributeName: [UIColor whiteColor],
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

#pragma mark NSKeyValueObserving

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *, id> *)change context:(void *)context {
    if (context == DWQRScanViewContext) {
        id newValue = nil;
        NSKeyValueChange changeType = [change[NSKeyValueChangeKindKey] unsignedIntegerValue];
        if (changeType == NSKeyValueChangeSetting) {
            newValue = change[NSKeyValueChangeNewKey];
            id oldValue = change[NSKeyValueChangeOldKey];
            if ([newValue isEqual:oldValue]) {
                return;
            }
        }
        
        id value = (newValue != [NSNull null]) ? newValue : nil;
        
        if ([keyPath isEqualToString:kQRCodeObjectKeyPath]) {
            [self handleQRCodeObject:value];
        }
        else if ([keyPath isEqualToString:kQRCodeObjectTypeKeyPath]) {
            [self updateQRCodeLayer:self.qrCodeLayer forObject:self.viewModel.qrCodeObject];
        }
        else {
            NSAssert(NO, @"Unhandled keypath %@", keyPath);
        }
    }
}

@end

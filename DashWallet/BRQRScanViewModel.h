//
//  BRQRScanViewModel.h
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class AVCaptureSession;
@class AVMetadataMachineReadableCodeObject;
@class BRPaymentRequest;
@class BRPaymentProtocolRequest;

typedef NS_ENUM(NSUInteger, QRCodeObjectType) {
    QRCodeObjectTypeProcessing,
    QRCodeObjectTypeValid,
    QRCodeObjectTypeInvalid,
};

@interface QRCodeObject : NSObject

@property (readonly, strong, nonatomic) AVMetadataMachineReadableCodeObject *metadataObject;
@property (readonly, assign, nonatomic) QRCodeObjectType type;
@property (nullable, readonly, copy, nonatomic) NSString *errorMessage;

- (instancetype)init NS_UNAVAILABLE;

@end

//

@protocol BRQRScanViewModelDelegate;

@interface BRQRScanViewModel : NSObject

@property (readonly, class, getter=isTorchAvailable) BOOL torchAvailable;

@property (weak, nonatomic) id<BRQRScanViewModelDelegate> delegate;

@property (readonly, strong, nonatomic) AVCaptureSession *captureSession;
@property (readonly, assign, nonatomic, getter=isCameraDeniedOrRestricted) BOOL cameraDeniedOrRestricted;
@property (nullable, readonly, strong, nonatomic) QRCodeObject *qrCodeObject;

- (void)startPreview;
- (void)stopPreview;

- (void)switchTorch;

- (void)cancel;

@end

@protocol BRQRScanViewModelDelegate <NSObject>

- (void)qrScanViewModel:(BRQRScanViewModel *)viewModel
didScanStandardNonPaymentRequest:(BRPaymentRequest *)request;

- (void)qrScanViewModel:(BRQRScanViewModel *)viewModel
  didScanPaymentRequest:(BRPaymentRequest *)request
        protocolRequest:(BRPaymentProtocolRequest *)protocolRequest
                  error:(NSError *_Nullable)error;

- (void)qrScanViewModel:(BRQRScanViewModel *)viewModel
didScanBIP73PaymentProtocolRequest:(BRPaymentProtocolRequest *)protocolRequest;

- (void)qrScanViewModelDidCancel:(BRQRScanViewModel *)viewModel;

@end

NS_ASSUME_NONNULL_END

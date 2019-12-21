//
//  DWQRScanViewModel.m
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

#import <DashSync/DashSync.h>

#import "DWCaptureSessionManager.h"
#import "DWEnvironment.h"
#import "DWPaymentInput+Private.h"
#import "DWQRScanModel.h"

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const kReqeustTimeout = 5.0;
static NSTimeInterval const kResumeSearchTimeInterval = 1.0;

#pragma - QR Object

@interface QRCodeObject ()

@property (assign, nonatomic) QRCodeObjectType type;
@property (nullable, copy, nonatomic) NSString *errorMessage;

@end

@implementation QRCodeObject

- (instancetype)initWithMetadataObject:(AVMetadataMachineReadableCodeObject *)metadataObject {
    self = [super init];
    if (self) {
        _metadataObject = metadataObject;
    }
    return self;
}

- (void)setValid {
    self.errorMessage = nil;
    self.type = QRCodeObjectTypeValid;
}

- (void)setInvalidWithErrorMessage:(NSString *)errorMessage {
    self.errorMessage = errorMessage;
    self.type = QRCodeObjectTypeInvalid;
}

@end

#pragma mark - View Model

@interface DWQRScanModel () <DWCaptureSessionMetadataDelegate>

@property (assign, atomic) BOOL paused;
@property (nullable, strong, nonatomic) QRCodeObject *qrCodeObject;

@end

@implementation DWQRScanModel

- (instancetype)init {
    self = [super init];
    if (self) {
        [DWCaptureSessionManager sharedInstance].delegate = self;
    }
    return self;
}

- (void)dealloc {
    DSLogVerbose(@"☠️ %@", NSStringFromClass(self.class));
}

+ (BOOL)isTorchAvailable {
    return [DWCaptureSessionManager sharedInstance].isTorchAvailable;
}

- (AVCaptureSession *)captureSession {
    return [DWCaptureSessionManager sharedInstance].captureSession;
}

- (BOOL)isCameraDeniedOrRestricted {
    return [DWCaptureSessionManager sharedInstance].isCameraDeniedOrRestricted;
}

- (void)startPreviewCompletion:(void (^)(void))completion {
    [[DWCaptureSessionManager sharedInstance] startPreviewCompletion:completion];
}

- (void)stopPreview {
    [[DWCaptureSessionManager sharedInstance] stopPreview];
}

- (void)switchTorch {
    [[DWCaptureSessionManager sharedInstance] switchTorch];
}

- (void)cancel {
    [self.delegate qrScanModelDidCancel:self];
}

#pragma mark Private

- (void)pauseQRCodeSearch {
    self.paused = YES;
}

- (void)resumeQRCodeSearch {
    NSAssert([NSThread isMainThread], nil);
    self.paused = NO;
    self.qrCodeObject = nil;
}

- (nullable AVMetadataMachineReadableCodeObject *)preferredMetadataObjectInObjects:(NSArray<__kindof AVMetadataObject *> *)metadataObjects {
    AVMetadataMachineReadableCodeObject *anyObject = nil;
    for (__kindof AVMetadataObject *object in metadataObjects) {
        if (![object.type isEqual:AVMetadataObjectTypeQRCode]) {
            continue;
        }

        AVMetadataMachineReadableCodeObject *codeObject = object;

        DSChain *chain = [DWEnvironment sharedInstance].currentChain;
        NSString *addr = [codeObject.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        DSPaymentRequest *request = [DSPaymentRequest requestWithString:addr onChain:chain];
        if (request.isValid || [addr isValidDashPrivateKeyOnChain:chain] || [addr isValidDashBIP38Key]) {
            return codeObject;
        }
        else if (!anyObject) {
            anyObject = codeObject;
        }
    }

    return anyObject;
}

#pragma mark DWCaptureSessionMetadataDelegate

- (void)didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)metadataObjects {
    if (self.paused) {
        return;
    }

    [self pauseQRCodeSearch];

    AVMetadataMachineReadableCodeObject *codeObject = [self preferredMetadataObjectInObjects:metadataObjects];
    if (!codeObject) {
        [self resumeQRCodeSearch];

        return;
    }

    NSAssert(![NSThread isMainThread], nil);
    dispatch_sync(dispatch_get_main_queue(), ^{ // sync!
        self.qrCodeObject = [[QRCodeObject alloc] initWithMetadataObject:codeObject];
    });

    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    NSString *addr = [codeObject.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    DSPaymentRequest *request = [DSPaymentRequest requestWithString:addr onChain:chain];
    if (request.isValid || [addr isValidDashPrivateKeyOnChain:chain] || [addr isValidDashBIP38Key]) {
        dispatch_sync(dispatch_get_main_queue(), ^{ // sync!
            [self.qrCodeObject setValid];
        });

        if (request.r.length > 0) { // start fetching payment protocol request right away
            __weak typeof(self) weakSelf = self;
            [DSPaymentRequest
                     fetch:request.r
                    scheme:request.scheme
                   onChain:[DWEnvironment sharedInstance].currentChain
                   timeout:kReqeustTimeout
                completion:^(DSPaymentProtocolRequest *protocolRequest, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        __strong typeof(weakSelf) strongSelf = weakSelf;
                        if (!strongSelf) {
                            return;
                        }

                        if (error) {
                            request.r = nil;
                        }

                        if (error && !request.isValid) {
                            NSString *title = NSLocalizedString(@"Couldn't make payment", nil);
                            [strongSelf.delegate qrScanModel:strongSelf
                                              showErrorTitle:title
                                                     message:error.localizedDescription];
                        }

                        DWPaymentInput *paymentInput = [[DWPaymentInput alloc] initWithSource:DWPaymentInputSource_ScanQR];

                        if (error) {
                            // payment protocol fetch failed, so use standard request
                            paymentInput.request = request;
                        }
                        else {
                            paymentInput.protocolRequest = protocolRequest;
                        }

                        [strongSelf.delegate qrScanModel:strongSelf didScanPaymentInput:paymentInput];
                    });
                }];
        }
        else { // standard non payment protocol request
            dispatch_async(dispatch_get_main_queue(), ^{
                DWPaymentInput *paymentInput = [[DWPaymentInput alloc] initWithSource:DWPaymentInputSource_ScanQR];
                paymentInput.request = request;
                paymentInput.canChangeAmount = request.amount > 0;
                [self.delegate qrScanModel:self didScanPaymentInput:paymentInput];
            });
        }
    }
    else {
        __weak __typeof__(self) weakSelf = self;
        [DSPaymentRequest
                 fetch:request.r
                scheme:request.scheme
               onChain:[DWEnvironment sharedInstance].currentChain
               timeout:kReqeustTimeout
            completion:^(DSPaymentProtocolRequest *protocolRequest, NSError *error) { // check to see if it's a BIP73 url
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong __typeof__(weakSelf) strongSelf = weakSelf;

                    if (protocolRequest) {
                        [strongSelf.qrCodeObject setValid];
                        DWPaymentInput *paymentInput = [[DWPaymentInput alloc] initWithSource:DWPaymentInputSource_ScanQR];
                        paymentInput.protocolRequest = protocolRequest;
                        [strongSelf.delegate qrScanModel:strongSelf didScanPaymentInput:paymentInput];
                    }
                    else {
                        NSString *errorMessage = nil;
                        if (([request.scheme isEqual:@"dash"] && request.paymentAddress.length > 1) ||
                            [request.paymentAddress hasPrefix:@"X"] || [request.paymentAddress hasPrefix:@"7"]) {
                            errorMessage =
                                [NSString stringWithFormat:@"%@:\n%@",
                                                           NSLocalizedString(@"Not a valid Dash address", nil),
                                                           request.paymentAddress];
                        }
                        else {
                            errorMessage = NSLocalizedString(@"Not a Dash QR code", nil);
                        }
                        [strongSelf.qrCodeObject setInvalidWithErrorMessage:errorMessage];

                        [strongSelf performSelector:@selector(resumeQRCodeSearch) withObject:nil afterDelay:kResumeSearchTimeInterval];
                    }
                });
            }];
    }
}

@end

NS_ASSUME_NONNULL_END

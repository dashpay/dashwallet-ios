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

#import "DWCaptureSessionManager.h"

#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const STOP_PREVIEW_TIMEOUT = 3.0;
static NSTimeInterval const SESSION_KEEPALIVE = 6.0;

@interface DWCaptureSessionManager () <AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>

@property (null_resettable, nonatomic, strong) AVCaptureSession *captureSession;
@property (null_resettable, nonatomic, strong) dispatch_queue_t sessionQueue;
@property (null_resettable, nonatomic, strong) dispatch_queue_t metadataQueue;
@property (null_resettable, nonatomic, strong) dispatch_queue_t framesOutputQueue;
@property (nonatomic, assign, getter=isCaptureSessionConfigured) BOOL captureSessionConfigured;
@property (atomic, assign, getter=isActive) BOOL active;

@end

@implementation DWCaptureSessionManager

+ (instancetype)sharedInstance {
    static DWCaptureSessionManager *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    return _sharedInstance;
}

#pragma mark - Public

- (BOOL)isTorchAvailable {
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    return device.torchAvailable;
}

- (BOOL)isCameraDeniedOrRestricted {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    return (status == AVAuthorizationStatusDenied || status == AVAuthorizationStatusRestricted);
}

- (void)startPreviewCompletion:(void (^)(void))completion {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(stopPreviewInternal)
                                               object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(tearDown)
                                               object:nil];

    void (^doStartPreview)(void) = ^{
#if !TARGET_OS_SIMULATOR
        [self setupCaptureSessionIfNeeded];
#endif /* TARGET_OS_SIMULATOR */

        dispatch_async(self.sessionQueue, ^{
            self.active = YES;

            if (!self.captureSession.isRunning) {
                [self.captureSession startRunning];
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion();
                }
            });
        });
    };

    switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]) {
        case AVAuthorizationStatusNotDetermined: {
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                                     completionHandler:^(BOOL granted) {
                                         if (granted) {
                                             dispatch_async(dispatch_get_main_queue(), doStartPreview);
                                         }
                                     }];
            break;
        }

        case AVAuthorizationStatusRestricted:
        case AVAuthorizationStatusDenied: {
            break;
        }

        case AVAuthorizationStatusAuthorized: {
            doStartPreview();
            break;
        }
    }
}

- (void)stopPreview {
    self.active = NO;

    [self performSelector:@selector(stopPreviewInternal)
               withObject:nil
               afterDelay:STOP_PREVIEW_TIMEOUT];
}

- (void)switchTorch {
    NSAssert(self.isTorchAvailable, @"Torch is not available");
    if (!self.isTorchAvailable) {
        return;
    }

    dispatch_async(self.sessionQueue, ^{
        if (!self.captureSession.isRunning) {
            return;
        }

        NSError *error = nil;
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];

        if ([device lockForConfiguration:&error]) {
            device.torchMode = device.torchActive ? AVCaptureTorchModeOff : AVCaptureTorchModeOn;
            [device unlockForConfiguration];
        }
        else {
            DSLog(@"DWCaptureSessionManager: %@", error);
        }
    });
}

#pragma mark AVCaptureMetadataOutputObjectsDelegate

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)metadataObjects
              fromConnection:(AVCaptureConnection *)connection {
    if (!self.active) {
        return;
    }

    [self.delegate didOutputMetadataObjects:metadataObjects];
}

#pragma mark AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection {
    if (!self.frameDelegate) {
        return;
    }

    [self.frameDelegate didOutputSampleBuffer:sampleBuffer];
}

- (void)captureOutput:(AVCaptureOutput *)output
    didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer
         fromConnection:(AVCaptureConnection *)connection {
    // this is fine 🔥
}

#pragma mark Private

- (void)stopPreviewInternal {
    DSLog(@"DWCaptureSessionManager: Stopping preview...");
    dispatch_async(self.sessionQueue, ^{
        if (self.captureSession.isRunning) {
            [self.captureSession stopRunning];

            dispatch_async(dispatch_get_main_queue(), ^{
                DSLog(@"DWCaptureSessionManager: Preview has been stopped");
                [self performSelector:@selector(tearDown) withObject:nil afterDelay:SESSION_KEEPALIVE];
            });
        }
    });
}

- (void)setupCaptureSessionIfNeeded {
    if (self.isCaptureSessionConfigured) {
        return;
    }
    self.captureSessionConfigured = YES;

    dispatch_async(self.sessionQueue, ^{
        NSError *error = nil;
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
        if (error) {
            DSLog(@"DWCaptureSessionManager: %@", error);
        }
        if ([device lockForConfiguration:&error]) {
            if (device.isAutoFocusRangeRestrictionSupported) {
                device.autoFocusRangeRestriction = AVCaptureAutoFocusRangeRestrictionNear;
            }

            if ([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
                device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
            }

            [device unlockForConfiguration];
        }
        else {
            DSLog(@"DWCaptureSessionManager: %@", error);
        }

        [self.captureSession beginConfiguration];

        if (input && [self.captureSession canAddInput:input]) {
            [self.captureSession addInput:input];
        }

        AVCaptureMetadataOutput *output = [[AVCaptureMetadataOutput alloc] init];
        if ([self.captureSession canAddOutput:output]) {
            [self.captureSession addOutput:output];
        }
        [output setMetadataObjectsDelegate:self queue:self.metadataQueue];
        if ([output.availableMetadataObjectTypes containsObject:AVMetadataObjectTypeQRCode]) {
            output.metadataObjectTypes = @[ AVMetadataObjectTypeQRCode ];
        }

        AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
        videoOutput.alwaysDiscardsLateVideoFrames = YES;
        videoOutput.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)};
        [videoOutput setSampleBufferDelegate:self queue:self.framesOutputQueue];

        if ([self.captureSession canAddOutput:videoOutput]) {
            [self.captureSession addOutput:videoOutput];
        }
        else {
            DSLog(@"DWCaptureSessionManager: can't add AVCaptureVideoDataOutput");
        }

        AVCaptureConnection *connection = [videoOutput connectionWithMediaType:AVMediaTypeVideo];
        if (connection.supportsVideoOrientation) {
            connection.videoOrientation = AVCaptureVideoOrientationPortrait;
        }

        [self.captureSession commitConfiguration];
    });
}

- (void)tearDown {
    DSLog(@"DWCaptureSessionManager: Tearing down...");
    self.captureSession = nil;
    self.sessionQueue = nil;
    self.metadataQueue = nil;
    self.framesOutputQueue = nil;
    self.captureSessionConfigured = NO;
}

- (AVCaptureSession *)captureSession {
    if (!_captureSession) {
        _captureSession = [[AVCaptureSession alloc] init];
    }

    return _captureSession;
}

- (dispatch_queue_t)sessionQueue {
    if (!_sessionQueue) {
        _sessionQueue = dispatch_queue_create("DWQRScanViewModel.CaptureSession.queue", DISPATCH_QUEUE_SERIAL);
    }

    return _sessionQueue;
}

- (dispatch_queue_t)metadataQueue {
    if (!_metadataQueue) {
        _metadataQueue = dispatch_queue_create("DWQRScanViewModel.CaptureMetadataOutput.queue", DISPATCH_QUEUE_SERIAL);
    }

    return _metadataQueue;
}

- (dispatch_queue_t)framesOutputQueue {
    if (!_framesOutputQueue) {
        _framesOutputQueue = dispatch_queue_create("DWQRScanViewModel.VideoFramesOutput.queue", DISPATCH_QUEUE_SERIAL);
    }
    return _framesOutputQueue;
}

@end

NS_ASSUME_NONNULL_END

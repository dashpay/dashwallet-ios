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

@property (nullable, nonatomic, strong) AVCaptureSession *captureSession;
@property (nullable, nonatomic, strong) dispatch_queue_t sessionQueue;
@property (nullable, nonatomic, strong) dispatch_queue_t metadataQueue;
@property (nullable, nonatomic, strong) dispatch_queue_t framesOutputQueue;
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

    void (^doStartPreview)(void) = ^{
        // Mark the session active before any setup/start work. A teardown
        // already scheduled by an earlier `stopPreview` cannot be cancelled
        // (`dispatch_after` has no cancel), so it reads this flag on main and
        // bails instead — see `tearDown`.
        self.active = YES;
        [self setupCaptureSessionIfNeeded];

        // Bind the queue and session once. `setupCaptureSessionIfNeeded` is a
        // no-op when a session is already configured, so these can only be nil
        // if the camera is unavailable (no capture device — simulator, or a
        // device whose camera the system won't hand over).
        dispatch_queue_t queue = self.sessionQueue;
        AVCaptureSession *session = self.captureSession;
        if (!queue || !session) {
            return;
        }

        dispatch_async(queue, ^{
            if (!session.isRunning) {
                [session startRunning];
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

    dispatch_queue_t queue = self.sessionQueue;
    AVCaptureSession *session = self.captureSession;
    if (!queue || !session) {
        return;
    }

    dispatch_async(queue, ^{
        if (!session.isRunning) {
            return;
        }

        NSError *error = nil;
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];

        if ([device lockForConfiguration:&error]) {
            device.torchMode = device.torchActive ? AVCaptureTorchModeOff : AVCaptureTorchModeOn;
            [device unlockForConfiguration];
        }
        else {
            DWLog(@"DWCaptureSessionManager: %@", error);
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
    DWLog(@"DWCaptureSessionManager: Stopping preview...");
    dispatch_queue_t queue = self.sessionQueue;
    AVCaptureSession *session = self.captureSession;
    if (!queue || !session) {
        return;
    }

    dispatch_async(queue, ^{
        if (session.isRunning) {
            [session stopRunning];
        }

        // The delayed teardown is scheduled back on MAIN, not on the session
        // queue: `captureSession`, the three queues and `captureSessionConfigured`
        // are only ever read/written from main (startPreview / stopPreview are
        // both main-thread entry points), so keeping the state transition there
        // is what makes it race-free. Tearing down on the session queue instead
        // let `tearDown` nil `sessionQueue` while a concurrent `startPreview`
        // on main had already passed the `isCaptureSessionConfigured` check —
        // which then dispatched onto a NULL queue.
        dispatch_async(dispatch_get_main_queue(), ^{
            DWLog(@"DWCaptureSessionManager: Preview has been stopped");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SESSION_KEEPALIVE * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                               [self tearDown];
                           });
        });
    });
}

- (void)setupCaptureSessionIfNeeded {
    if (self.isCaptureSessionConfigured) {
        return;
    }

    // No capture device means no session to configure — the simulator, or a
    // device that won't vend the camera. `+[AVCaptureDeviceInput
    // deviceInputWithDevice:error:]` raises NSInvalidArgumentException on a nil
    // device, so bail before anything is allocated and leave
    // `captureSessionConfigured` NO. `startPreviewCompletion:` sees the nil
    // session and no-ops; the scan screen renders without a preview instead of
    // crashing. (This replaces the previous `#if !TARGET_OS_SIMULATOR` guard,
    // which only covered the simulator case.)
    if ([AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] == nil) {
        DWLog(@"DWCaptureSessionManager: no video capture device available");
        return;
    }

    self.captureSession = [[AVCaptureSession alloc] init];
    self.sessionQueue = dispatch_queue_create("DWQRScanViewModel.CaptureSession.queue", DISPATCH_QUEUE_SERIAL);
    self.metadataQueue = dispatch_queue_create("DWQRScanViewModel.CaptureMetadataOutput.queue", DISPATCH_QUEUE_SERIAL);
    self.framesOutputQueue = dispatch_queue_create("DWQRScanViewModel.VideoFramesOutput.queue", DISPATCH_QUEUE_SERIAL);
    self.captureSessionConfigured = YES;

    dispatch_async(self.sessionQueue, ^{
        NSError *error = nil;
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
        if (error) {
            DWLog(@"DWCaptureSessionManager: %@", error);
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
            DWLog(@"DWCaptureSessionManager: %@", error);
        }

        [self.captureSession beginConfiguration];

        if (input && [self.captureSession canAddInput:input]) {
            [self.captureSession addInput:input];
        }

        AVCaptureMetadataOutput *output = [[AVCaptureMetadataOutput alloc] init];
        if ([self.captureSession canAddOutput:output]) {
            [self.captureSession addOutput:output];
        }
        [output setMetadataObjectsDelegate:self
                                     queue:self.metadataQueue];
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
            DWLog(@"DWCaptureSessionManager: can't add AVCaptureVideoDataOutput");
        }

        AVCaptureConnection *connection = [videoOutput connectionWithMediaType:AVMediaTypeVideo];
        if (connection.supportsVideoOrientation) {
            connection.videoOrientation = AVCaptureVideoOrientationPortrait;
        }

        [self.captureSession commitConfiguration];
    });
}

/// Releases the session and its queues. Runs on MAIN — the same thread as
/// `startPreviewCompletion:` / `stopPreview`, so `active` and the session state
/// below are never read and written concurrently.
- (void)tearDown {
    DWLog(@"DWCaptureSessionManager: Tearing down...");

    // The scanner was reopened inside the keepalive window; the live session is
    // in use. `active` is set on main by `doStartPreview`, so this check cannot
    // race the assignment.
    if (self.active) {
        return;
    }

    AVCaptureSession *session = self.captureSession;
    if (session) {
        [session beginConfiguration];
        for (AVCaptureOutput *output in [session.outputs copy]) {
            if ([output isKindOfClass:[AVCaptureMetadataOutput class]]) {
                [(AVCaptureMetadataOutput *)output setMetadataObjectsDelegate:nil queue:NULL];
            }
            else if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
                [(AVCaptureVideoDataOutput *)output setSampleBufferDelegate:nil queue:NULL];
            }
            [session removeOutput:output];
        }
        for (AVCaptureInput *input in [session.inputs copy]) {
            [session removeInput:input];
        }
        [session commitConfiguration];
    }

    self.captureSession = nil;
    self.sessionQueue = nil;
    self.metadataQueue = nil;
    self.framesOutputQueue = nil;
    self.captureSessionConfigured = NO;
}

@end

NS_ASSUME_NONNULL_END

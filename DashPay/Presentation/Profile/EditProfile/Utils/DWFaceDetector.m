//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWFaceDetector.h"

#import <Vision/Vision.h>

NS_ASSUME_NONNULL_BEGIN

static CGImagePropertyOrientation UIImageOrientationToCGImageOrientation(UIImageOrientation orientation) {
    switch (orientation) {
        case UIImageOrientationUp:
            return kCGImagePropertyOrientationUp;
        case UIImageOrientationDown:
            return kCGImagePropertyOrientationDown;
        case UIImageOrientationRight:
            return kCGImagePropertyOrientationRight;
        case UIImageOrientationUpMirrored:
            return kCGImagePropertyOrientationUpMirrored;
        case UIImageOrientationDownMirrored:
            return kCGImagePropertyOrientationDownMirrored;
        case UIImageOrientationLeftMirrored:
            return kCGImagePropertyOrientationLeftMirrored;
        case UIImageOrientationRightMirrored:
            return kCGImagePropertyOrientationRightMirrored;
        default:
            return kCGImagePropertyOrientationUp;
    }
}

@interface DWFaceDetector ()

@property (nonatomic, readonly, strong) VNDetectFaceRectanglesRequest *request;

@end

NS_ASSUME_NONNULL_END

@implementation DWFaceDetector

- (instancetype)initWithImage:(UIImage *)image completion:(void (^)(CGRect roi))completion {
    NSParameterAssert(image.CGImage);

    self = [super init];
    if (self) {
        CGSize imageSize = image.size;
        _request = [[VNDetectFaceRectanglesRequest alloc] initWithCompletionHandler:^(VNRequest *_Nonnull request, NSError *_Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                VNFaceObservation *observation = request.results.firstObject;
                if (error != nil || ![observation isKindOfClass:VNFaceObservation.class]) {
                    completion(CGRectZero);
                }
                else {
                    CGRect rect = observation.boundingBox;
                    CGFloat x = rect.origin.x * imageSize.width;
                    CGFloat w = rect.size.width * imageSize.width;
                    CGFloat h = rect.size.height * imageSize.height;
                    CGFloat y = imageSize.height * (1 - rect.origin.y) - h;
                    completion(CGRectMake(x, y, w, h));
                }
            });
        }];

        VNImageRequestHandler *requestHandler =
            [[VNImageRequestHandler alloc] initWithCGImage:image.CGImage
                                               orientation:UIImageOrientationToCGImageOrientation(image.imageOrientation)
                                                   options:@{}];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *error = nil;
            [requestHandler performRequests:@[ self.request ] error:&error];
            if (error != nil) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(CGRectZero);
                });
            }
        });
    }
    return self;
}

@end

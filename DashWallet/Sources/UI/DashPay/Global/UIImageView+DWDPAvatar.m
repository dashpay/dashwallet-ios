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

#import "UIImageView+DWDPAvatar.h"

#import "DWDPAvatarView.h"
#import <SDWebImage/SDWebImage.h>
#import <TOCropViewController/UIImage+CropRotate.h>

@implementation UIImageView (DWDPAvatar)

- (void)dw_setAvatarWithURLString:(NSString *)urlString completion:(void (^)(UIImage *_Nullable image))completion {
    if (urlString.length == 0) {
        if (completion) {
            completion(nil);
        }
        return;
    }


    NSURL *url = [NSURL URLWithString:urlString];
    NSURL *originalURL = [url copy];
    if (url == nil) {
        if (completion) {
            completion(nil);
        }
        return;
    }

    // has crop params
    CGRect cropRectOfInterest = CGRectNull;
    if (urlString.length > 0 && [urlString rangeOfString:DPCropParameterName].location != NSNotFound) {
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        NSMutableArray<NSURLQueryItem *> *queryItems = [components.queryItems mutableCopy];
        NSURLQueryItem *cropItem = nil;
        for (NSURLQueryItem *item in components.queryItems) {
            if ([item.name isEqualToString:DPCropParameterName]) {
                cropItem = item;
                break;
            }
        }

        if (cropItem != nil) {
            [queryItems removeObject:cropItem];

            NSArray<NSString *> *params = [cropItem.value componentsSeparatedByString:@","];
            if (params.count != 4) {
                params = [cropItem.value componentsSeparatedByString:@"%2C"];
            }

            if (params.count == 4) {
                CGFloat x = [params[0] doubleValue];
                CGFloat y = [params[1] doubleValue];
                CGFloat w = [params[2] doubleValue] - x;
                CGFloat h = [params[3] doubleValue] - y;
                cropRectOfInterest = CGRectMake(x, y, w, h);
            }

            components.queryItems = queryItems.count > 0 ? queryItems : nil;
            url = components.URL;
        }
    }

    __weak typeof(self) weakSelf = self;
    [self sd_setImageWithURL:url
                   completed:^(UIImage *_Nullable image, NSError *_Nullable error, SDImageCacheType cacheType, NSURL *_Nullable imageURL) {
                       __strong typeof(weakSelf) strongSelf = weakSelf;
                       if (!strongSelf) {
                           return;
                       }

                       if (image == nil || CGRectIsNull(cropRectOfInterest)) {
                           if (completion) {
                               completion(image);
                           }

                           return;
                       }

                       dispatch_async([strongSelf.class processingQueue], ^{
                           NSString *croppedKey = originalURL.absoluteString;

                           UIImage *croppedImage = [SDImageCache.sharedImageCache imageFromCacheForKey:croppedKey];
                           if (croppedImage != nil) {
                               dispatch_async(dispatch_get_main_queue(), ^{
                                   if (completion) {
                                       completion(croppedImage);
                                   }
                               });

                               return;
                           }

                           CGSize imageSize = image.size;
                           CGRect cropRect = CGRectMake(cropRectOfInterest.origin.x * imageSize.width,
                                                        cropRectOfInterest.origin.y * imageSize.height,
                                                        cropRectOfInterest.size.width * imageSize.width,
                                                        cropRectOfInterest.size.height * imageSize.height);
                           croppedImage = [image croppedImageWithFrame:cropRect angle:0 circularClip:NO];
                           if (croppedImage) {
                               [SDImageCache.sharedImageCache storeImage:croppedImage forKey:croppedKey completion:nil];
                           }

                           dispatch_async(dispatch_get_main_queue(), ^{
                               if (completion) {
                                   completion(croppedImage);
                               }
                           });
                       });
                   }];
}

+ (dispatch_queue_t)processingQueue {
    static dispatch_queue_t _sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = dispatch_queue_create("dw.dp.avatar-processing-queue", DISPATCH_QUEUE_SERIAL);
    });
    return _sharedInstance;
}

@end

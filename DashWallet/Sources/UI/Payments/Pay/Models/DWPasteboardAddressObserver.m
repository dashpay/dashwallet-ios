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

#import "DWPasteboardAddressObserver.h"

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

NSString *DWPasteboardObserverNotification = @"DWPasteboardObserverNotification";
static NSTimeInterval const TIMER_INTERVAL = 1.0;

@interface DWPasteboardAddressObserver ()

@property (nonatomic, assign) NSInteger changeCount;
@property (copy, nonatomic) NSArray<NSString *> *contents;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nullable, strong, nonatomic) dispatch_source_t timer;

@end

@implementation DWPasteboardAddressObserver

- (instancetype)init {
    self = [super init];
    if (self) {
        _contents = @[];
        _changeCount = NSNotFound;
        _queue = dispatch_queue_create("DWPasteboardAddressObserver.queue", DISPATCH_QUEUE_SERIAL);

        [self checkPasteboardContentsCompletion:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActiveNotification)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [self stopIntervalObserving];
}

- (void)startIntervalObserving {
    if (self.timer) {
        return;
    }

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
    // tolerance is of 10 percent: NSEC_PER_SEC / 10
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, TIMER_INTERVAL * NSEC_PER_SEC, NSEC_PER_SEC / 10);
    dispatch_source_set_event_handler(timer, ^{
        [self checkPasteboardContentsInternalCompletion:nil];
    });
    dispatch_resume(timer);

    self.timer = timer;
}

- (void)stopIntervalObserving {
    if (self.timer == nil) {
        return;
    }

    dispatch_source_cancel(self.timer);

    self.timer = nil;
}

- (void)checkPasteboardContentsCompletion:(nullable void (^)(void))completion {
    dispatch_async(self.queue, ^{
        [self checkPasteboardContentsInternalCompletion:completion];
    });
}

#pragma mark Notifications

- (void)applicationDidBecomeActiveNotification {
    [self checkPasteboardContentsCompletion:nil];
}

#pragma mark Private

- (void)checkPasteboardContentsInternalCompletion:(nullable void (^)(void))completion {
    NSAssert(![NSThread isMainThread], @"Should run on background thread");

    if (self.changeCount == [UIPasteboard generalPasteboard].changeCount) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), completion);
        }

        return;
    }

    self.changeCount = [UIPasteboard generalPasteboard].changeCount;

    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    NSMutableOrderedSet<NSString *> *resultSet = [NSMutableOrderedSet orderedSet];
    NSCharacterSet *whitespacesSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];

    if (pasteboard.hasStrings) {
        NSString *str = [pasteboard.string stringByTrimmingCharactersInSet:whitespacesSet];
        if (str.length > 0) {
            NSCharacterSet *separatorsSet = [NSCharacterSet alphanumericCharacterSet].invertedSet;

            [resultSet addObject:str];
            [resultSet addObjectsFromArray:[str componentsSeparatedByCharactersInSet:separatorsSet]];
        }
    }

    if (pasteboard.hasImages) {
        UIImage *img = [UIPasteboard generalPasteboard].image;
        if (img) {
            @synchronized([CIContext class]) {
                NSDictionary<CIContextOption, id> *options = @{kCIContextUseSoftwareRenderer : @(YES)};
                CIContext *context = [CIContext contextWithOptions:options];
                if (!context) {
                    context = [CIContext context];
                }

                CIDetector *detector = [CIDetector detectorOfType:CIDetectorTypeQRCode
                                                          context:context
                                                          options:nil];
                CGImageRef cgImage = img.CGImage;
                if (detector && cgImage) {
                    CIImage *ciImage = [CIImage imageWithCGImage:cgImage];
                    NSArray<CIFeature *> *features = [detector featuresInImage:ciImage];
                    for (CIQRCodeFeature *qr in features) {
                        NSString *str = [qr.messageString stringByTrimmingCharactersInSet:whitespacesSet];
                        if (str.length > 0) {
                            [resultSet addObject:str];
                        }
                    }
                }
            }
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        self.contents = resultSet.array;

        if (completion) {
            completion();
        }

        [[NSNotificationCenter defaultCenter] postNotificationName:DWPasteboardObserverNotification
                                                            object:nil];
    });
}

@end

NS_ASSUME_NONNULL_END

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

@interface DWPasteboardAddressObserver ()

@property (nonatomic, assign) NSInteger changeCount;
@property (copy, nonatomic) NSArray<NSString *> *contents;

@end

@implementation DWPasteboardAddressObserver

- (instancetype)init {
    self = [super init];
    if (self) {
        _contents = @[];
        _changeCount = NSNotFound;

        [self checkPasteboardContents];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(pasteboardChangedNotification)
                                                     name:UIPasteboardChangedNotification
                                                   object:nil];
    }
    return self;
}


#pragma mark Notifications

- (void)pasteboardChangedNotification {
    [self checkPasteboardContents];
}

#pragma mark Private

- (void)checkPasteboardContents {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (self.changeCount == [UIPasteboard generalPasteboard].changeCount) {
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

            [[NSNotificationCenter defaultCenter] postNotificationName:DWPasteboardObserverNotification
                                                                object:nil];
        });
    });
}

@end

NS_ASSUME_NONNULL_END

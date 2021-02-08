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

#import "DWPasteboardAddressExtractor.h"

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DWPasteboardAddressExtractor

- (NSArray<NSString *> *)extractAddresses {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    NSMutableOrderedSet<NSString *> *resultSet = [NSMutableOrderedSet orderedSet];
    NSCharacterSet *whitespacesSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];

    NSString *str = [pasteboard.string stringByTrimmingCharactersInSet:whitespacesSet];
    if (str.length > 0) {
        NSCharacterSet *separatorsSet = [NSCharacterSet alphanumericCharacterSet].invertedSet;

        [resultSet addObject:str];
        [resultSet addObjectsFromArray:[str componentsSeparatedByCharactersInSet:separatorsSet]];
    }

    UIImage *img = [UIPasteboard generalPasteboard].image;
    if (img) {
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
    return resultSet.array;
}

@end

NS_ASSUME_NONNULL_END

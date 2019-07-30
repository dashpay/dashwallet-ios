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

#import "DWSeedWordModel+DWLayoutSupport.h"

#import "DWUIKit.h"
#import "NSString+DWTextSize.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat VerticalPadding(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
        case DWSeedPhraseType_Verify:
            return 10.0;
        case DWSeedPhraseType_Select:
            return 13.0;
    }
}

static CGFloat HorizontalPadding(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
        case DWSeedPhraseType_Verify:
            return 8.0;
        case DWSeedPhraseType_Select:
            return 20.0;
    }
}

@implementation DWSeedWordModel (DWLayoutSupport)

+ (UIFont *)dw_wordFontForType:(DWSeedPhraseType)type {
    switch (type) {
        case DWSeedPhraseType_Preview:
        case DWSeedPhraseType_Verify:
            return [UIFont dw_fontForTextStyle:UIFontTextStyleTitle3];
        case DWSeedPhraseType_Select:
            return [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
    }
}

- (CGSize)dw_sizeWithMaxWidth:(CGFloat)maxWidth type:(DWSeedPhraseType)type {
    NSString *const text = self.word;
    NSAssert(text.length > 0, @"Invalid seed word");

    UIFont *const font = [self.class dw_wordFontForType:type];
    const CGSize textSize = [text dw_textSizeWithFont:font maxWidth:maxWidth];

    const CGFloat horizontalPadding = HorizontalPadding(type);
    const CGFloat verticalPadding = VerticalPadding(type);

    const CGSize size = CGSizeMake(ceil(textSize.width + horizontalPadding * 2),
                                   ceil(textSize.height + verticalPadding * 2));

    return size;
}

@end

NS_ASSUME_NONNULL_END

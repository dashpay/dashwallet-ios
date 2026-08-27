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

#import "DWRecoverTextView.h"

#import "DWSeedWordModel+DWLayoutSupport.h"
#import "DWUIKit.h"
#import "NSString+DWTextSize.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const CORNER_RADIUS = 8.0;
static UIEdgeInsets const TEXT_INSETS = {12.0, 12.0, 12.0, 12.0};
static CGFloat const VERTICAL_PADDING = 10.0; // same as in DWSeedWordModel+DWLayoutSupport.h

@interface DWRecoverTextView () <NSLayoutManagerDelegate>

@end

@implementation DWRecoverTextView

- (instancetype)initWithFrame:(CGRect)frame textContainer:(nullable NSTextContainer *)textContainer {
    self = [super initWithFrame:frame textContainer:textContainer];
    if (self) {
        [self recoverTextView_setup];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self recoverTextView_setup];
    }
    return self;
}

- (void)recoverTextView_setup {
    self.backgroundColor = [UIColor dw_backgroundColor];
    self.layer.cornerRadius = CORNER_RADIUS;
    self.layer.masksToBounds = YES;
    self.layoutManager.delegate = self;
    self.font = [DWSeedWordModel dw_wordFontForType:DWSeedPhraseType_Verify];
    self.textColor = [UIColor dw_dashBlueColor];
    self.textContainerInset = TEXT_INSETS;
    self.autocorrectionType = UITextAutocorrectionTypeNo;
    self.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.returnKeyType = UIReturnKeyDone;
    self.textAlignment = NSTextAlignmentCenter;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contentSizeCategoryDidChangeNotification:)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
}

- (CGRect)caretRectForPosition:(UITextPosition *)position {
    CGRect originalRect = [super caretRectForPosition:position];
    UIFont *font = self.font;
    originalRect.size.height = font.pointSize - font.descender;
    return originalRect;
}

- (CGFloat)minimumHeight {
    const CGSize letterMaxSize = CGSizeMake(160.0, 160.0);
    const CGFloat lineHeight = [@"Q" dw_textSizeWithFont:self.font maxSize:letterMaxSize].height;
    const NSInteger numberOfLines = 5;
    const CGFloat textViewApproximateHeight = lineHeight * numberOfLines +
                                              VERTICAL_PADDING * (numberOfLines - 1) +
                                              TEXT_INSETS.top + TEXT_INSETS.bottom;

    return textViewApproximateHeight;
}

#pragma mark - NSLayoutManagerDelegate

- (CGFloat)layoutManager:(NSLayoutManager *)layoutManager
    lineSpacingAfterGlyphAtIndex:(NSUInteger)glyphIndex
    withProposedLineFragmentRect:(CGRect)rect {
    return VERTICAL_PADDING;
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification:(NSNotification *)notification {
    self.font = [DWSeedWordModel dw_wordFontForType:DWSeedPhraseType_Verify];
    [self setNeedsLayout];
}

@end

NS_ASSUME_NONNULL_END

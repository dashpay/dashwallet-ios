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

#import "DWSeedPhraseView.h"

#import "DWSeedPhraseModel.h"
#import "DWSeedWordView.h"
#import "DevicesCompatibility.h"
#import "UIColor+DWStyle.h"

NS_ASSUME_NONNULL_BEGIN

static UIColor *BackgroundColor(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
            return [UIColor dw_backgroundColor];
        case DWSeedPhraseType_Select:
            return [UIColor dw_secondaryBackgroundColor];
    }
}

static CGFloat LineSpacing(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
            return 0.0;
        case DWSeedPhraseType_Select:
            return 8.0;
    }
}

static CGFloat InteritemSpacing(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
            return 0.0;
        case DWSeedPhraseType_Select:
            return 8.0;
    }
}

static CGFloat ContentVerticalPadding(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
            return 10.0;
        case DWSeedPhraseType_Select:
            return 8.0;
    }
}

static CGFloat CornerRadius(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
            return 8.0;
        case DWSeedPhraseType_Select:
            return 0.0;
    }
}

static BOOL MasksToBounds(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
            return YES;
        case DWSeedPhraseType_Select:
            return NO;
    }
}

static NSUInteger MaxWordsInARow(void) {
    if (IS_IPHONE_5_OR_LESS) {
        return NSUIntegerMax;
    }
    else {
        return 4;
    }
}

#pragma mark - Layout Support

@interface DWSeedPhraseRow : NSObject

@property (readonly, nonatomic, assign) DWSeedPhraseType type;

@property (readonly, nonatomic, strong) NSMutableArray<DWSeedWordView *> *wordViews;
@property (readonly, nonatomic, strong) NSMutableArray<NSValue *> *wordSizes;

@property (readonly, nonatomic, assign) CGFloat height;
@property (readonly, nonatomic, assign) CGFloat width;

@end

@implementation DWSeedPhraseRow

- (instancetype)initWithType:(DWSeedPhraseType)type {
    self = [super init];
    if (self) {
        _type = type;

        _wordViews = [NSMutableArray array];
        _wordSizes = [NSMutableArray array];
    }
    return self;
}

- (BOOL)canAddWordWithSize:(CGSize)wordSize parentWidth:(CGFloat)parentWidth {
    const NSUInteger count = self.wordViews.count;
    const BOOL isEmpty = (count == 0);
    if (isEmpty) {
        // always allow to add new word if empty
        return YES;
    }

    if (count < MaxWordsInARow()) {
        const CGFloat currentWidth = self.width;
        const CGFloat interitemSpacing = InteritemSpacing(self.type);
        const BOOL isFits = (currentWidth + wordSize.width + interitemSpacing <= parentWidth);

        return isFits;
    }

    return NO;
}

- (void)addWordView:(DWSeedWordView *)wordView size:(CGSize)size {
    [self.wordViews addObject:wordView];
    [self.wordSizes addObject:[NSValue valueWithCGSize:size]];
}

- (CGFloat)height {
    CGFloat height = 0.0;

    for (NSValue *wordSize in self.wordSizes) {
        const CGSize size = wordSize.CGSizeValue;
        height = MAX(height, size.height);
    }

    return height;
}

- (CGFloat)width {
    CGFloat width = 0.0;

    for (NSValue *wordSize in self.wordSizes) {
        const CGSize size = wordSize.CGSizeValue;
        width += size.width;
    }

    const NSUInteger count = self.wordSizes.count;
    if (count > 1) {
        const CGFloat interitemSpacing = InteritemSpacing(self.type);
        width += interitemSpacing * (count - 1);
    }

    return width;
}

@end

#pragma mark - View

@interface DWSeedPhraseView ()

@property (readonly, nonatomic, assign) DWSeedPhraseType type;

@property (nullable, nonatomic, copy) NSArray<DWSeedWordView *> *wordViews;
@property (nonatomic, assign) CGFloat currentHeight;

@end

@implementation DWSeedPhraseView

- (instancetype)initWithType:(DWSeedPhraseType)type {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _type = type;

        self.backgroundColor = BackgroundColor(type);

        self.layer.cornerRadius = CornerRadius(type);
        self.layer.masksToBounds = MasksToBounds(type);

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(contentSizeCategoryDidChangeNotification:)
                                                     name:UIContentSizeCategoryDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)setModel:(nullable DWSeedPhraseModel *)model {
    _model = model;

    [self reloadData];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    [self layoutWordViews];
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, self.currentHeight);
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification:(NSNotification *)notification {
    [self reloadData];
}

#pragma mark - Private

- (void)reloadData {
    [self.wordViews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    self.wordViews = nil;

    NSMutableArray<DWSeedWordView *> *wordViews = [NSMutableArray array];
    for (DWSeedWordModel *wordModel in self.model.words) {
        DWSeedWordView *wordView = [[DWSeedWordView alloc] initWithType:self.type];
        wordView.model = wordModel;
        [self addSubview:wordView];
        [wordViews addObject:wordView];
    }
    self.wordViews = wordViews;

    [self setNeedsLayout];
}

- (void)setCurrentHeight:(CGFloat)currentHeight {
    _currentHeight = currentHeight;

    [self invalidateIntrinsicContentSize];
}

// O(n^2)
- (void)layoutWordViews {
    if (self.wordViews.count == 0) {
        self.currentHeight = 0.0;

        return;
    }

    const DWSeedPhraseType type = self.type;
    const CGFloat width = CGRectGetWidth(self.bounds);
    const CGFloat lineSpacing = LineSpacing(type);
    const CGFloat interitemSpacing = InteritemSpacing(type);

    NSMutableArray<DWSeedPhraseRow *> *rows = [NSMutableArray array];

    DWSeedPhraseRow *currentRow = [[DWSeedPhraseRow alloc] initWithType:type];
    [rows addObject:currentRow];

    for (DWSeedWordView *wordView in self.wordViews) {
        const CGSize wordSize = [DWSeedWordView sizeForModel:wordView.model maxWidth:width type:type];

        const BOOL canAddWord = [currentRow canAddWordWithSize:wordSize parentWidth:width];
        if (!canAddWord) {
            currentRow = [[DWSeedPhraseRow alloc] initWithType:type];
            [rows addObject:currentRow];
        }

        [currentRow addWordView:wordView size:wordSize];
    }

    const CGFloat contentPadding = ContentVerticalPadding(type);
    CGFloat y = contentPadding;

    for (DWSeedPhraseRow *row in rows) {
        CGFloat x = (width - row.width) / 2.0;
        NSAssert(x >= 0.0, @"Invalid layout: row width > view width");

        for (NSUInteger i = 0; i < row.wordViews.count; i++) {
            DWSeedWordView *const wordView = row.wordViews[i];
            const CGSize size = [row.wordSizes[i] CGSizeValue];

            wordView.frame = CGRectMake(x, y, size.width, size.height);

            x += size.width + interitemSpacing;
        }

        y += row.height + lineSpacing;
    }

    y += contentPadding;

    self.currentHeight = y;
}

@end

NS_ASSUME_NONNULL_END

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

#import "DWSeedPhraseViewLayout.h"

#import "DWSeedPhraseModel.h"
#import "DWSeedWordModel+DWLayoutSupport.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat LineSpacing(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
        case DWSeedPhraseType_Verify:
            return 0.0;
        case DWSeedPhraseType_Select:
            return 8.0;
    }
}


static CGFloat ContentVerticalPadding(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
        case DWSeedPhraseType_Verify:
            return 10.0;
        case DWSeedPhraseType_Select:
            return 8.0;
    }
}

@interface DWSeedPhraseViewLayout ()

@property (readonly, nonatomic, assign) DWSeedPhraseType type;
@property (readonly, nonatomic, strong) NSMutableArray<NSValue *> *frames;
@property (nonatomic, assign) CGFloat height;
@property (nonatomic, assign) BOOL didPerformLayout;

@end


@implementation DWSeedPhraseViewLayout

- (instancetype)initWithSeedPhrase:(DWSeedPhraseModel *)seedPhrase type:(DWSeedPhraseType)type {
    self = [super init];
    if (self) {
        _seedPhrase = seedPhrase;
        _type = type;
        _frames = [NSMutableArray array];
    }
    return self;
}

// O(n^2)
- (void)performLayout {
    NSAssert(self.dataSource, @"dataSource is not set");

    [self invalidateLayout];

    const DWSeedPhraseType type = self.type;
    const CGFloat width = [self.dataSource viewWidthForSeedPhraseViewLayout:self];
    const CGFloat lineSpacing = LineSpacing(type);
    const CGFloat interitemSpacing = DWInteritemSpacing(type);

    NSMutableArray<DWSeedPhraseRow *> *rows = [NSMutableArray array];

    DWSeedPhraseRow *currentRow = [[DWSeedPhraseRow alloc] initWithType:type];
    [rows addObject:currentRow];

    for (DWSeedWordModel *wordModel in self.seedPhrase.words) {
        const CGSize wordSize = [wordModel dw_sizeWithMaxWidth:width type:type];

        const BOOL canAddWord = [currentRow canAddWordWithSize:wordSize parentWidth:width];
        if (!canAddWord) {
            currentRow = [[DWSeedPhraseRow alloc] initWithType:type];
            [rows addObject:currentRow];
        }

        [currentRow addWord:wordModel
                       size:wordSize];
    }

    const CGFloat contentPadding = ContentVerticalPadding(type);
    CGFloat y = contentPadding;

    for (DWSeedPhraseRow *row in rows) {
        CGFloat x = (width - row.width) / 2.0;
        NSAssert(x >= 0.0, @"Invalid layout: row width > view width");

        for (NSUInteger i = 0; i < row.wordModels.count; i++) {
            DWSeedWordModel *const wordModel = row.wordModels[i];
            const CGSize size = [row.wordSizes[i] CGSizeValue];

            const CGRect frame = CGRectMake(x, y, size.width, size.height);
            [self.frames addObject:[NSValue valueWithCGRect:frame]];

            x += size.width + interitemSpacing;
        }

        y += row.height + lineSpacing;
    }

    y += contentPadding;

    self.height = y;

    self.didPerformLayout = YES;
}

- (CGRect)frameForWordAtIndex:(NSUInteger)index {
    NSAssert(self.didPerformLayout, @"Requesting frames before calling performLayout method");

    NSAssert(index != NSNotFound, @"Invalid index");
    if (index == NSNotFound) {
        return CGRectZero;
    }

    NSAssert(index >= 0 && index < self.frames.count, @"Invalid index");

    if (index >= 0 && index < self.frames.count) {
        NSValue *frameValue = self.frames[index];
        return frameValue.CGRectValue;
    }

    return CGRectZero;
}

#pragma mark - Private

- (void)invalidateLayout {
    self.didPerformLayout = NO;
    [self.frames removeAllObjects];
}

@end

NS_ASSUME_NONNULL_END

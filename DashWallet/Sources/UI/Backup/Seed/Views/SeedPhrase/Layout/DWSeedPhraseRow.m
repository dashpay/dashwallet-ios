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

#import "DWSeedPhraseRow.h"

#import "DevicesCompatibility.h"

NS_ASSUME_NONNULL_BEGIN

CGFloat DWInteritemSpacing(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
        case DWSeedPhraseType_Verify:
            return 0.0;
        case DWSeedPhraseType_Select:
            return 8.0;
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

@interface DWSeedPhraseRow ()

@property (readonly, nonatomic, assign) DWSeedPhraseType type;
@property (readonly, nonatomic, strong) NSMutableArray<DWSeedWordModel *> *mutableWordModels;
@property (readonly, nonatomic, strong) NSMutableArray<NSValue *> *mutableWordSizes;

@end

@implementation DWSeedPhraseRow

- (instancetype)initWithType:(DWSeedPhraseType)type {
    self = [super init];
    if (self) {
        _type = type;

        _mutableWordModels = [NSMutableArray array];
        _mutableWordSizes = [NSMutableArray array];
    }
    return self;
}

- (NSArray<DWSeedWordModel *> *)wordModels {
    return [self.mutableWordModels copy];
}

- (NSArray<NSValue *> *)wordSizes {
    return [self.mutableWordSizes copy];
}

- (BOOL)canAddWordWithSize:(CGSize)wordSize parentWidth:(CGFloat)parentWidth {
    const NSUInteger count = self.mutableWordModels.count;
    const BOOL isEmpty = (count == 0);
    if (isEmpty) {
        // always allow to add new word if empty
        return YES;
    }

    if (count < MaxWordsInARow()) {
        const CGFloat currentWidth = self.width;
        const CGFloat interitemSpacing = DWInteritemSpacing(self.type);
        const BOOL isFits = (currentWidth + wordSize.width + interitemSpacing <= parentWidth);

        return isFits;
    }

    return NO;
}

- (void)addWord:(DWSeedWordModel *)wordModel size:(CGSize)size {
    [self.mutableWordModels addObject:wordModel];
    [self.mutableWordSizes addObject:[NSValue valueWithCGSize:size]];
}

- (CGFloat)height {
    CGFloat height = 0.0;

    for (NSValue *wordSize in self.mutableWordSizes) {
        const CGSize size = wordSize.CGSizeValue;
        height = MAX(height, size.height);
    }

    return height;
}

- (CGFloat)width {
    CGFloat width = 0.0;

    for (NSValue *wordSize in self.mutableWordSizes) {
        const CGSize size = wordSize.CGSizeValue;
        width += size.width;
    }

    const NSUInteger count = self.mutableWordSizes.count;
    if (count > 1) {
        const CGFloat interitemSpacing = DWInteritemSpacing(self.type);
        width += interitemSpacing * (count - 1);
    }

    return width;
}

@end

NS_ASSUME_NONNULL_END

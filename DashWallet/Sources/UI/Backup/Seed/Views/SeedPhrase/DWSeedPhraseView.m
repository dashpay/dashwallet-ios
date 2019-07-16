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
#import "DWSeedPhraseViewLayout.h"
#import "DWSeedWordModel.h"
#import "DWSeedWordView.h"
#import "UIColor+DWStyle.h"

NS_ASSUME_NONNULL_BEGIN

static UIColor *BackgroundColor(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
        case DWSeedPhraseType_Verify:
            return [UIColor dw_backgroundColor];
        case DWSeedPhraseType_Select:
            return [UIColor dw_secondaryBackgroundColor];
    }
}

static CGFloat CornerRadius(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
        case DWSeedPhraseType_Verify:
            return 8.0;
        case DWSeedPhraseType_Select:
            return 0.0;
    }
}

static BOOL MasksToBounds(DWSeedPhraseType type) {
    switch (type) {
        case DWSeedPhraseType_Preview:
        case DWSeedPhraseType_Verify:
            return YES;
        case DWSeedPhraseType_Select:
            return NO;
    }
}

@interface DWSeedPhraseView () <DWSeedPhraseViewLayoutDataSource>

@property (readonly, nonatomic, assign) DWSeedPhraseType type;

@property (nullable, nonatomic, copy) NSArray<DWSeedWordView *> *wordViews;
@property (nullable, nonatomic, strong) DWSeedPhraseViewLayout *layout;

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

    self.layout = [[DWSeedPhraseViewLayout alloc] initWithSeedPhrase:model type:self.type];
    self.layout.dataSource = self;

    [self reloadData];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    [self layoutWordViews];
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, self.layout ? self.layout.height : 0.0);
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification:(NSNotification *)notification {
    [self reloadData];
}

#pragma mark - DWSeedPhraseViewLayoutDataSource

- (CGFloat)viewWidthForSeedPhraseViewLayout:(DWSeedPhraseViewLayout *)layout {
    return CGRectGetWidth(self.bounds);
}

#pragma mark - Private

- (void)reloadData {
    [self.wordViews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    self.wordViews = nil;

    NSMutableArray<DWSeedWordView *> *wordViews = [NSMutableArray array];
    for (DWSeedWordModel *wordModel in self.model.words) {
        DWSeedWordView *wordView = [[DWSeedWordView alloc] initWithType:self.type];
        wordView.model = wordModel;
        if (self.type == DWSeedPhraseType_Select) {
            [wordView addTarget:self
                          action:@selector(wordViewAction:)
                forControlEvents:UIControlEventTouchUpInside];
        }
        [self addSubview:wordView];
        [wordViews addObject:wordView];
    }
    self.wordViews = wordViews;

    [self setNeedsLayout];
}

- (void)layoutWordViews {
    if (self.wordViews.count == 0) {
        return;
    }

    [self.layout performLayout];

    for (DWSeedWordView *wordView in self.wordViews) {
        DWSeedWordModel *wordModel = wordView.model;
        const NSUInteger index = [self.wordViews indexOfObject:wordView];
        const CGRect frame = [self.layout frameForWordAtIndex:index];
        wordView.frame = frame;
    }

    [self invalidateIntrinsicContentSize];
}

#pragma mark - Actions

- (void)wordViewAction:(DWSeedWordView *)sender {
    NSParameterAssert(self.delegate);

    DWSeedWordModel *wordModel = sender.model;
    if (wordModel.isSelected) {
        return;
    }

    BOOL allowed = [self.delegate seedPhraseView:self allowedToSelectWord:wordModel];
    if (allowed) {
        [self.delegate seedPhraseView:self didSelectWord:wordModel];
    }
    else {
        sender.userInteractionEnabled = NO;
        __weak typeof(sender) weakSender = sender;
        [sender animateDiscardedSelectionWithCompletion:^{
            weakSender.userInteractionEnabled = YES;
        }];
    }
}

@end

NS_ASSUME_NONNULL_END

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

#import "DWVerifySeedPhraseContentView.h"

#import "DWSeedPhraseTitledView.h"
#import "DWSeedPhraseView.h"
#import "DWSeedWordView.h"
#import "DWUIKit.h"
#import "DWVerifySeedPhraseModel.h"

static CGFloat const DEFAULT_PADDING = 64.0;
static CGFloat const COMPACT_PADDING = 16.0;
static CGFloat const BOTTOM_PADDING = 12.0;

static CGFloat HintTopPadding(void) {
    if (IS_IPHONE_5_OR_LESS) {
        return 16.0;
    }
    else {
        return 24.0;
    }
}

static CGFloat HintBottomPadding(void) {
    if (IS_IPHONE_5_OR_LESS) {
        return 8.0;
    }
    else {
        return 16.0;
    }
}

NS_ASSUME_NONNULL_BEGIN

@interface DWVerifySeedPhraseContentView () <DWSeedPhraseViewDelegate>

@property (nonatomic, strong) DWSeedPhraseTitledView *verificationSeedPhraseView;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) DWSeedPhraseView *shuffledSeedPhraseView;

@property (nonatomic, strong) NSLayoutConstraint *verificationSeedPhraseTopConstraint;

@property (nonatomic, assign) BOOL initialAnimationCompleted;

@end

@implementation DWVerifySeedPhraseContentView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

        DWSeedPhraseTitledView *verificationSeedPhraseView = [[DWSeedPhraseTitledView alloc] initWithType:DWSeedPhraseType_Verify];
        verificationSeedPhraseView.translatesAutoresizingMaskIntoConstraints = NO;
        verificationSeedPhraseView.title = NSLocalizedString(@"Verify", nil);
        [self addSubview:verificationSeedPhraseView];
        _verificationSeedPhraseView = verificationSeedPhraseView;

        UILabel *hintLabel = [[UILabel alloc] init];
        hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
        hintLabel.backgroundColor = self.backgroundColor;
        hintLabel.textAlignment = NSTextAlignmentCenter;
        hintLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
        hintLabel.textColor = [UIColor dw_secondaryTextColor];
        hintLabel.adjustsFontForContentSizeCategory = YES;
        hintLabel.numberOfLines = 0;
        hintLabel.text = NSLocalizedString(@"Please tap on the words from your recovery phrase in the right order", nil);
        [self addSubview:hintLabel];
        _hintLabel = hintLabel;

        DWSeedPhraseView *shuffledSeedPhraseView = [[DWSeedPhraseView alloc] initWithType:DWSeedPhraseType_Select];
        shuffledSeedPhraseView.translatesAutoresizingMaskIntoConstraints = NO;
        shuffledSeedPhraseView.delegate = self;
        [self addSubview:shuffledSeedPhraseView];
        _shuffledSeedPhraseView = shuffledSeedPhraseView;

        _verificationSeedPhraseTopConstraint = [verificationSeedPhraseView.topAnchor constraintEqualToAnchor:self.topAnchor
                                                                                                    constant:COMPACT_PADDING];

        [NSLayoutConstraint activateConstraints:@[
            _verificationSeedPhraseTopConstraint,
            [verificationSeedPhraseView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [verificationSeedPhraseView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [hintLabel.topAnchor constraintGreaterThanOrEqualToAnchor:verificationSeedPhraseView.bottomAnchor
                                                             constant:HintTopPadding()],
            [hintLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [hintLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [shuffledSeedPhraseView.topAnchor constraintEqualToAnchor:hintLabel.bottomAnchor
                                                             constant:HintBottomPadding()],
            [shuffledSeedPhraseView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [shuffledSeedPhraseView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [shuffledSeedPhraseView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    if (!CGSizeEqualToSize(self.bounds.size, [self intrinsicContentSize])) {
        [self invalidateIntrinsicContentSize];
    }
}

- (CGSize)intrinsicContentSize {
    const CGFloat height = self.verificationSeedPhraseTopConstraint.constant +
                           [self minimumContentHeightWithoutTopPadding];

    return CGSizeMake(self.visibleSize.width, MAX(height, self.visibleSize.height));
}

- (void)setModel:(nullable DWVerifySeedPhraseModel *)model {
    _model = model;

    // init shuffled view with normal model first
    // shuffled model will be set animated later (viewDidAppear)

    DWSeedPhraseModel *normalOrderedModel = model.seedPhrase;
    self.verificationSeedPhraseView.model = normalOrderedModel;
    self.shuffledSeedPhraseView.model = normalOrderedModel;
}

- (void)setVisibleSize:(CGSize)visibleSize {
    _visibleSize = visibleSize;

    const CGFloat contentHeight = COMPACT_PADDING + [self minimumContentHeightWithoutTopPadding];
    if (visibleSize.height - contentHeight >= DEFAULT_PADDING * 2.0) {
        self.verificationSeedPhraseTopConstraint.constant = DEFAULT_PADDING;
    }
    else {
        self.verificationSeedPhraseTopConstraint.constant = COMPACT_PADDING;
    }

    [self setNeedsLayout];
}

- (void)viewDidAppear {
    if (!self.initialAnimationCompleted) {
        [self.shuffledSeedPhraseView setModel:self.model.shuffledSeedPhrase
                                    animation:DWSeedPhraseViewAnimation_Shuffle];
    }
    self.initialAnimationCompleted = YES;
}

- (CGFloat)minimumContentHeightWithoutTopPadding {
    const CGFloat contentHeight = self.verificationSeedPhraseView.intrinsicContentSize.height +
                                  HintTopPadding() +
                                  self.hintLabel.intrinsicContentSize.height +
                                  HintBottomPadding() +
                                  self.shuffledSeedPhraseView.intrinsicContentSize.height;

    return contentHeight;
}

#pragma mark - DWSeedPhraseViewDelegate

- (BOOL)seedPhraseView:(DWSeedPhraseView *)view allowedToSelectWord:(DWSeedWordModel *)wordModel {
    return [self.model allowedToSelectWord:wordModel];
}

- (void)seedPhraseView:(DWSeedPhraseView *)view didSelectWord:(DWSeedWordModel *)wordModel {
    [self.model selectWord:wordModel];

    if (self.model.seedPhraseHasBeenVerified) {
        // show result when animation ends
        dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DW_VERIFY_APPEAR_ANIMATION_DURATION * NSEC_PER_SEC));
        dispatch_after(when, dispatch_get_main_queue(), ^{
            [self.delegate verifySeedPhraseContentViewDidVerify:self];
        });
    }
}

@end

NS_ASSUME_NONNULL_END

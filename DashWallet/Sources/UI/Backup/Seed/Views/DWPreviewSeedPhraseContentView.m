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

#import "DWPreviewSeedPhraseContentView.h"

#import "DWCheckbox.h"
#import "DWSeedPhraseTitledView.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const DEFAULT_PADDING = 64.0;
static CGFloat const COMPACT_PADDING = 16.0;
static CGFloat const BOTTOM_PADDING = 12.0;

@interface DWPreviewSeedPhraseContentView ()

@property (nonatomic, strong) DWSeedPhraseTitledView *seedPhraseView;
@property (nonatomic, strong) DWCheckbox *confirmationCheckbox;

@property (nonatomic, strong) NSLayoutConstraint *seedPhraseTopConstraint;

@end

@implementation DWPreviewSeedPhraseContentView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        DWSeedPhraseTitledView *seedPhraseView = [[DWSeedPhraseTitledView alloc] initWithType:DWSeedPhraseType_Preview];
        seedPhraseView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:seedPhraseView];
        _seedPhraseView = seedPhraseView;

        DWCheckbox *confirmationCheckbox = [[DWCheckbox alloc] initWithFrame:CGRectZero];
        confirmationCheckbox.translatesAutoresizingMaskIntoConstraints = NO;
        confirmationCheckbox.title = NSLocalizedString(@"I wrote it down", nil);
        [self addSubview:confirmationCheckbox];
        _confirmationCheckbox = confirmationCheckbox;

        _seedPhraseTopConstraint = [seedPhraseView.topAnchor constraintEqualToAnchor:self.topAnchor
                                                                            constant:COMPACT_PADDING];

        [NSLayoutConstraint activateConstraints:@[
            _seedPhraseTopConstraint,
            [seedPhraseView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [seedPhraseView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            // top constraint on checkbox is not needed basically (since we calculate intrinsicContentSize)
            // BUT in case of refactoring/updating layout code it will produce a warning
            [confirmationCheckbox.topAnchor constraintGreaterThanOrEqualToAnchor:seedPhraseView.bottomAnchor],
            [confirmationCheckbox.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [confirmationCheckbox.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor],
            [confirmationCheckbox.trailingAnchor constraintGreaterThanOrEqualToAnchor:self.trailingAnchor],
            [confirmationCheckbox.bottomAnchor constraintEqualToAnchor:self.bottomAnchor
                                                              constant:-BOTTOM_PADDING],
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
    const CGFloat height = self.seedPhraseTopConstraint.constant +
                           [self minimumContentHeightWithoutTopPadding];

    return CGSizeMake(self.visibleSize.width, MAX(height, self.visibleSize.height));
}

- (nullable DWSeedPhraseControllerModel *)model {
    return self.seedPhraseView.model;
}

- (void)setModel:(nullable DWSeedPhraseControllerModel *)model {
    self.seedPhraseView.model = model;
}

- (void)setVisibleSize:(CGSize)visibleSize {
    _visibleSize = visibleSize;

    const CGFloat contentHeight = COMPACT_PADDING + [self minimumContentHeightWithoutTopPadding];
    if (visibleSize.height - contentHeight >= DEFAULT_PADDING * 2.0) {
        self.seedPhraseTopConstraint.constant = DEFAULT_PADDING;
    }
    else {
        self.seedPhraseTopConstraint.constant = COMPACT_PADDING;
    }

    [self setNeedsLayout];
}

- (CGFloat)minimumContentHeightWithoutTopPadding {
    const CGFloat contentHeight = self.seedPhraseView.intrinsicContentSize.height +
                                  COMPACT_PADDING +
                                  self.confirmationCheckbox.intrinsicContentSize.height +
                                  BOTTOM_PADDING;

    return contentHeight;
}

@end

NS_ASSUME_NONNULL_END

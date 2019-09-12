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

#import "DWSeedPhraseTitledView.h"

#import "DWSeedPhraseView.h"
#import "DWSeedUIConstants.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static UIColor *TitleColorForStyle(DWSeedPhraseTitledViewTitleStyle titleStyle) {
    switch (titleStyle) {
        case DWSeedPhraseTitledViewTitleStyle_Default:
            return [UIColor dw_darkTitleColor];
        case DWSeedPhraseTitledViewTitleStyle_Error:
            return [UIColor dw_redColor];
    }
}

@interface DWSeedPhraseTitledView ()

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) DWSeedPhraseView *seedPhraseView;

@end

@implementation DWSeedPhraseTitledView

- (instancetype)initWithType:(DWSeedPhraseType)type {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.backgroundColor = self.backgroundColor;
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle3];
        titleLabel.textColor = TitleColorForStyle(DWSeedPhraseTitledViewTitleStyle_Default);
        titleLabel.adjustsFontForContentSizeCategory = YES;
        titleLabel.numberOfLines = 0;
        [self addSubview:titleLabel];
        _titleLabel = titleLabel;

        DWSeedPhraseView *seedPhraseView = [[DWSeedPhraseView alloc] initWithType:type];
        seedPhraseView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:seedPhraseView];
        _seedPhraseView = seedPhraseView;

        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
            [titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [seedPhraseView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                                     constant:DWTitleSeedPhrasePadding()],
            [seedPhraseView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [seedPhraseView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [seedPhraseView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
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
    const CGFloat width = self.bounds.size.width;
    const CGFloat height = self.titleLabel.intrinsicContentSize.height +
                           DWTitleSeedPhrasePadding() +
                           self.seedPhraseView.intrinsicContentSize.height;
    return CGSizeMake(width, height);
}

- (nullable DWSeedPhraseModel *)model {
    return self.seedPhraseView.model;
}

- (void)setModel:(nullable DWSeedPhraseModel *)model {
    self.seedPhraseView.model = model;
}

- (nullable NSString *)title {
    return self.titleLabel.text;
}

- (void)setTitle:(nullable NSString *)title {
    self.titleLabel.text = title;
}

- (void)setTitleStyle:(DWSeedPhraseTitledViewTitleStyle)titleStyle {
    _titleStyle = titleStyle;

    self.titleLabel.textColor = TitleColorForStyle(titleStyle);
}

- (void)prepareForAppearanceAnimation {
    [self.seedPhraseView prepareForSequenceAnimation];
}

- (void)showSeedPhraseAnimated {
    [self.seedPhraseView showSeedPhraseAnimatedAsSequence];
}

- (void)updateSeedPhraseModelAnimated:(DWSeedPhraseModel *)seedPhrase {
    [self.seedPhraseView setModel:seedPhrase animation:DWSeedPhraseViewAnimation_Sequence];
}

@end

NS_ASSUME_NONNULL_END

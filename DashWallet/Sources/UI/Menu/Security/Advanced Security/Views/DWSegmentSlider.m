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

#import "DWSegmentSlider.h"

#import <MMSegmentSlider/MMSegmentSlider.h>

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const LABELS_SPACING = 8.0;
static CGFloat const SLIDER_HEIGHT = 40.0;

@interface DWSegmentSlider ()

@property (readonly, nonatomic, strong) UILabel *leftLabel;
@property (readonly, nonatomic, strong) UILabel *rightLabel;
@property (readonly, nonatomic, strong) MMSegmentSlider *segmentSlider;
@property (readonly, nonatomic, strong) UISelectionFeedbackGenerator *feedbackGenerator;

@end

@implementation DWSegmentSlider

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self dwSegmentSlider_commonInit];
    }

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self dwSegmentSlider_commonInit];
    }

    return self;
}

+ (UIColor *)valuesTextColor {
    return [UIColor dw_quaternaryTextColor];
}

+ (UIFont *)valuesTextFont {
    return [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
}

- (void)dwSegmentSlider_commonInit {
    self.backgroundColor = [UIColor dw_backgroundColor];

    UILabel *leftLabel = [self.class segmentLabel];
    leftLabel.textAlignment = NSTextAlignmentLeft;
    [self addSubview:leftLabel];
    _leftLabel = leftLabel;

    UILabel *rightLabel = [self.class segmentLabel];
    rightLabel.textAlignment = NSTextAlignmentRight;
    [self addSubview:rightLabel];
    _rightLabel = rightLabel;

    MMSegmentSlider *segmentSlider = [[MMSegmentSlider alloc] initWithFrame:CGRectZero];
    segmentSlider.translatesAutoresizingMaskIntoConstraints = NO;
    segmentSlider.backgroundColor = [UIColor dw_backgroundColor];
    segmentSlider.basicColor = [UIColor dw_segmentSliderColor];
    segmentSlider.selectedValueColor = [UIColor dw_dashBlueColor];
    segmentSlider.useCircles = NO;
    segmentSlider.stopItemHeight = 10.0;
    segmentSlider.stopItemWidth = 1.0;
    segmentSlider.sliderWidth = 1.0;
    segmentSlider.horizontalInsets = 15.0;
    segmentSlider.circlesRadiusForSelected = 15.0;
    segmentSlider.values = @[];
    [segmentSlider addTarget:self
                      action:@selector(segmentSliderAction:)
            forControlEvents:UIControlEventValueChanged];
    [self addSubview:segmentSlider];
    _segmentSlider = segmentSlider;

    UISelectionFeedbackGenerator *feedbackGenerator = [[UISelectionFeedbackGenerator alloc] init];
    [feedbackGenerator prepare];
    _feedbackGenerator = feedbackGenerator;

    // Layout

    [NSLayoutConstraint activateConstraints:@[
        [leftLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
        [leftLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],

        [rightLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
        [rightLabel.leadingAnchor constraintEqualToAnchor:leftLabel.trailingAnchor
                                                 constant:LABELS_SPACING],
        [rightLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [leftLabel.widthAnchor constraintEqualToAnchor:rightLabel.widthAnchor],

        [segmentSlider.topAnchor constraintEqualToAnchor:leftLabel.bottomAnchor],
        [segmentSlider.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [segmentSlider.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [segmentSlider.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [segmentSlider.heightAnchor constraintEqualToConstant:SLIDER_HEIGHT],
    ]];
}

- (nullable NSString *)leftText {
    return self.leftLabel.text;
}

- (void)setLeftText:(nullable NSString *)leftText {
    self.leftLabel.text = leftText;
}

- (nullable NSString *)rightText {
    return self.rightLabel.text;
}

- (void)setRightText:(nullable NSString *)rightText {
    self.rightLabel.text = rightText;
}

- (nullable NSAttributedString *)leftAttributedText {
    return self.leftLabel.attributedText;
}

- (void)setLeftAttributedText:(nullable NSAttributedString *)leftAttributedText {
    self.leftLabel.attributedText = leftAttributedText;
}

- (nullable NSAttributedString *)rightAttributedText {
    return self.rightLabel.attributedText;
}

- (void)setRightAttributedText:(nullable NSAttributedString *)rightAttributedText {
    self.rightLabel.attributedText = rightAttributedText;
}

- (NSArray<id<NSCopying>> *)values {
    return self.segmentSlider.values;
}

- (void)setValues:(NSArray<id<NSCopying>> *)values {
    self.segmentSlider.values = values;
}

- (NSInteger)selectedItemIndex {
    return self.segmentSlider.selectedItemIndex;
}

- (void)setSelectedItemIndex:(NSInteger)selectedItemIndex {
    self.segmentSlider.selectedItemIndex = selectedItemIndex;
}

- (void)setSelectedItemIndex:(NSInteger)selectedItemIndex animated:(BOOL)animated {
    [self.segmentSlider setSelectedItemIndex:selectedItemIndex animated:animated];
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    self.segmentSlider.basicColor = [UIColor dw_segmentSliderColor];
    self.segmentSlider.selectedValueColor = [UIColor dw_dashBlueColor];
}

#pragma mark - Actions

- (void)segmentSliderAction:(MMSegmentSlider *)sender {
    [self.feedbackGenerator selectionChanged];
    [self.feedbackGenerator prepare];

    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

#pragma mark - Private

+ (UILabel *)segmentLabel {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.backgroundColor = [UIColor dw_backgroundColor];
    label.textColor = [self valuesTextColor];
    label.font = [self valuesTextFont];
    label.adjustsFontForContentSizeCategory = YES;
    label.minimumScaleFactor = 0.5;
    label.adjustsFontSizeToFitWidth = YES;

    return label;
}

@end

NS_ASSUME_NONNULL_END

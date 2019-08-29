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

#import "DWConfirmPaymentRowView.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const SEPARATOR = 1.0;
static CGFloat const SPACING = 16.0;

@interface DWConfirmPaymentRowView ()

@property (readonly, nonatomic, strong) CALayer *separatorLayer;

@end

@implementation DWConfirmPaymentRowView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self confirmPaymentRowViewCommonInit];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self confirmPaymentRowViewCommonInit];
    }
    return self;
}

- (void)confirmPaymentRowViewCommonInit {
    self.backgroundColor = [UIColor dw_backgroundColor];

    CALayer *separatorLayer = [CALayer layer];
    separatorLayer.backgroundColor = [UIColor dw_separatorLineColor].CGColor;
    [self.layer addSublayer:separatorLayer];
    _separatorLayer = separatorLayer;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.minimumScaleFactor = 0.5;
    titleLabel.numberOfLines = 0;
    titleLabel.textColor = [UIColor dw_quaternaryTextColor];
    titleLabel.textAlignment = NSTextAlignmentLeft;
    [self addSubview:titleLabel];
    _titleLabel = titleLabel;

    UILabel *detailLabel = [[UILabel alloc] init];
    detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    detailLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
    detailLabel.adjustsFontForContentSizeCategory = YES;
    detailLabel.adjustsFontSizeToFitWidth = YES;
    detailLabel.minimumScaleFactor = 0.5;
    detailLabel.numberOfLines = 0;
    detailLabel.textColor = [UIColor dw_darkTitleColor];
    detailLabel.textAlignment = NSTextAlignmentRight;
    [self addSubview:detailLabel];
    _detailLabel = detailLabel;

    [titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh - 1
                                                forAxis:UILayoutConstraintAxisHorizontal];
    [titleLabel setContentHuggingPriority:UILayoutPriorityDefaultLow + 1
                                  forAxis:UILayoutConstraintAxisHorizontal];
    [detailLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh + 1
                                                 forAxis:UILayoutConstraintAxisHorizontal];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [titleLabel.widthAnchor constraintGreaterThanOrEqualToAnchor:self.widthAnchor
                                                          multiplier:0.35],

        [detailLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
        [detailLabel.leadingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor
                                                  constant:SPACING],
        [detailLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [detailLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    ]];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    const CGSize size = self.bounds.size;
    self.separatorLayer.frame = CGRectMake(0.0, 0.0, size.width, SEPARATOR);
}

@end

NS_ASSUME_NONNULL_END

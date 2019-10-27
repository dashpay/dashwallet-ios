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

#import "DWTitleDetailCellView.h"

#import "DWUIKit.h"
#import <DashSync/UIView+DSFindConstraint.h>

NS_ASSUME_NONNULL_BEGIN

static CGFloat const SEPARATOR = 1.0;
static CGFloat const SPACING = 16.0;
static CGFloat const SMALL_PADDING = 12.0;

@interface DWTitleDetailCellView ()

@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) UILabel *detailLabel;
@property (readonly, nonatomic, strong) UIStackView *stackView;
@property (readonly, nonatomic, strong) CALayer *separatorLayer;

@end

@implementation DWTitleDetailCellView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self titleDetailCellViewCommonInit];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self titleDetailCellViewCommonInit];
    }
    return self;
}

- (void)titleDetailCellViewCommonInit {
    self.backgroundColor = [UIColor dw_backgroundColor];

    CALayer *separatorLayer = [CALayer layer];
    separatorLayer.backgroundColor = [UIColor dw_separatorLineColor].CGColor;
    [self.layer addSublayer:separatorLayer];
    _separatorLayer = separatorLayer;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.minimumScaleFactor = 0.5;
    titleLabel.numberOfLines = 0;
    titleLabel.textColor = [UIColor dw_quaternaryTextColor];
    titleLabel.textAlignment = NSTextAlignmentLeft;
    _titleLabel = titleLabel;

    UILabel *detailLabel = [[UILabel alloc] init];
    detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    detailLabel.adjustsFontForContentSizeCategory = YES;
    detailLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
    detailLabel.adjustsFontSizeToFitWidth = YES;
    detailLabel.minimumScaleFactor = 0.5;
    detailLabel.numberOfLines = 0;
    detailLabel.textColor = [UIColor dw_secondaryTextColor];
    detailLabel.textAlignment = NSTextAlignmentRight;
    _detailLabel = detailLabel;

    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ titleLabel, detailLabel ]];
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    stackView.axis = UILayoutConstraintAxisHorizontal;
    stackView.alignment = UIStackViewAlignmentCenter;
    stackView.spacing = SPACING;
    [self addSubview:stackView];
    _stackView = stackView;

    [NSLayoutConstraint activateConstraints:@[
        [stackView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [titleLabel.widthAnchor constraintGreaterThanOrEqualToAnchor:self.widthAnchor
                                                          multiplier:0.35],
    ]];
}

- (void)setContentPadding:(DWTitleDetailCellViewPadding)contentPadding {
    _contentPadding = contentPadding;

    const CGFloat padding = contentPadding == DWTitleDetailCellViewPadding_None ? 0 : SMALL_PADDING;
    NSLayoutConstraint *leadingConstraint =
        [self.stackView ds_findContraintForAttribute:NSLayoutAttributeLeading];
    leadingConstraint.constant = padding;

    NSLayoutConstraint *trailingConstraint =
        [self.stackView ds_findContraintForAttribute:NSLayoutAttributeTrailing];
    trailingConstraint.constant = -padding;
}

- (void)setSeparatorPosition:(DWTitleDetailCellViewSeparatorPosition)separatorPosition {
    _separatorPosition = separatorPosition;

    [self setNeedsLayout];
}

- (void)setModel:(nullable id<DWTitleDetailItem>)model {
    _model = model;

    switch (model.style) {
        case DWTitleDetailItem_Default: {
            self.detailLabel.adjustsFontSizeToFitWidth = YES;
            self.detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            self.detailLabel.numberOfLines = 0;

            break;
        }
        case DWTitleDetailItem_TruncatedSingleLine: {
            self.detailLabel.adjustsFontSizeToFitWidth = NO;
            self.detailLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
            self.detailLabel.numberOfLines = 1;

            break;
        }
    }

    if (model.title) {
        self.titleLabel.hidden = NO;
        self.titleLabel.text = model.title;
    }
    else {
        self.titleLabel.hidden = YES;
    }

    if (model.plainDetail) {
        self.detailLabel.hidden = NO;
        self.detailLabel.text = model.plainDetail;
    }
    else if (model.attributedDetail) {
        self.detailLabel.hidden = NO;
        self.detailLabel.attributedText = model.attributedDetail;
    }
    else {
        self.detailLabel.hidden = YES;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];

    const CGSize size = self.bounds.size;
    const CGFloat y = (self.separatorPosition == DWTitleDetailCellViewSeparatorPosition_Top
                           ? 0.0
                           : size.height - SEPARATOR);
    const CGFloat height = (self.separatorPosition == DWTitleDetailCellViewSeparatorPosition_Hidden
                                ? 0.0
                                : SEPARATOR);
    self.separatorLayer.frame = CGRectMake(0.0, y, size.width, height);
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    self.separatorLayer.backgroundColor = [UIColor dw_separatorLineColor].CGColor;
}

@end

NS_ASSUME_NONNULL_END

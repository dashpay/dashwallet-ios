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

#import "DWBaseFormTableViewCell.h"

#import "DWShadowView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

CGFloat const DW_FORM_CELL_VERTICAL_PADDING = 24.0;
CGFloat const DW_FORM_CELL_SPACING = 10.0;

static CGFloat const CORNER_RADIUS = 8.0;

static CGFloat SeparatorHeight(void) {
    return 1.0 / [UIScreen mainScreen].scale;
}

@interface DWFormCellShadowView : UIView

@property (nonatomic, assign) DWFormCellRoundMask roundMask;

@property (readonly, nonatomic, strong) UIView *shadowContentView;
@property (readonly, nonatomic, strong) DWShadowView *shadowView;

@end

@implementation DWFormCellShadowView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIView *shadowContentView = [[UIView alloc] initWithFrame:CGRectZero];
        shadowContentView.clipsToBounds = YES;
        [self addSubview:shadowContentView];
        _shadowContentView = shadowContentView;

        DWShadowView *shadowView = [[DWShadowView alloc] initWithFrame:CGRectZero];
        [shadowContentView addSubview:shadowView];
        _shadowView = shadowView;
    }
    return self;
}

- (void)setRoundMask:(DWFormCellRoundMask)roundMask {
    _roundMask = roundMask;

    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    const CGFloat dx = self.shadowView.layer.shadowRadius * 2.0;

    CGRect maskRect = CGRectInset(self.bounds, -dx, 0.0);
    CGRect shadowRect = self.bounds;
    shadowRect.origin.x = dx;

    if (self.roundMask & DWFormCellRoundMask_Top) {
        maskRect.origin.y = -dx;
        maskRect.size.height += dx;

        shadowRect.origin.y = dx;

        if (self.roundMask & DWFormCellRoundMask_Bottom) {
            maskRect.size.height += dx;
        }
    }
    else if (self.roundMask & DWFormCellRoundMask_Bottom) {
        maskRect.size.height += dx;
    }

    self.shadowContentView.frame = maskRect;
    self.shadowView.frame = shadowRect;
}

@end

@interface DWBaseFormTableViewCell ()

@property (readonly, nonatomic, strong) DWFormCellShadowView *shadowView;
@property (readonly, nonatomic, strong) UIView *separatorView;
@property (readonly, nonatomic, strong) NSLayoutConstraint *separatorHeightConstraint;

@end

@implementation DWBaseFormTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(nullable NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];
        self.contentView.backgroundColor = self.backgroundColor;

        self.selectionStyle = UITableViewCellSelectionStyleNone;

        UIView *contentView = self.contentView;

        DWFormCellShadowView *shadowView = [[DWFormCellShadowView alloc] initWithFrame:CGRectZero];
        shadowView.translatesAutoresizingMaskIntoConstraints = NO;
        [contentView addSubview:shadowView];
        _shadowView = shadowView;

        UIView *roundedContentView = [[UIView alloc] initWithFrame:CGRectZero];
        roundedContentView.translatesAutoresizingMaskIntoConstraints = NO;
        roundedContentView.backgroundColor = [UIColor dw_backgroundColor];
        roundedContentView.layer.cornerRadius = CORNER_RADIUS;
        roundedContentView.layer.masksToBounds = YES;
        roundedContentView.layer.rasterizationScale = [UIScreen mainScreen].scale;
        roundedContentView.layer.shouldRasterize = YES;
        [shadowView addSubview:roundedContentView];
        _roundedContentView = roundedContentView;

        UIView *separatorView = [[UIView alloc] initWithFrame:CGRectZero];
        separatorView.translatesAutoresizingMaskIntoConstraints = NO;
        separatorView.backgroundColor = [UIColor dw_separatorLineColor];
        [contentView addSubview:separatorView];

        UILayoutGuide *margins = contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [shadowView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
            [shadowView.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
            [shadowView.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],

            [roundedContentView.topAnchor constraintEqualToAnchor:shadowView.topAnchor],
            [roundedContentView.leadingAnchor constraintEqualToAnchor:shadowView.leadingAnchor],
            [roundedContentView.bottomAnchor constraintEqualToAnchor:shadowView.bottomAnchor],
            [roundedContentView.trailingAnchor constraintEqualToAnchor:shadowView.trailingAnchor],

            [separatorView.topAnchor constraintEqualToAnchor:shadowView.bottomAnchor],
            [separatorView.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
            [separatorView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
            [separatorView.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
            (_separatorHeightConstraint = [separatorView.heightAnchor constraintEqualToConstant:SeparatorHeight()]),
        ]];
    }

    return self;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];

    if ([self shouldAnimatePressWhenHighlighted]) {
        [self dw_pressedAnimation:DWPressedAnimationStrength_Light pressed:highlighted];
    }
}

- (void)setRoundMask:(DWFormCellRoundMask)roundMask {
    _roundMask = roundMask;

    CACornerMask maskedCorners = 0;
    BOOL shouldShowSeparator = YES;

    if (roundMask & DWFormCellRoundMask_Top) {
        maskedCorners |= kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner; // TL | TR
    }

    if (roundMask & DWFormCellRoundMask_Bottom) {
        maskedCorners |= kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner; // BL | BR
        shouldShowSeparator = NO;
    }

    self.roundedContentView.layer.maskedCorners = maskedCorners;
    self.shadowView.roundMask = roundMask;
    self.separatorHeightConstraint.constant = shouldShowSeparator ? SeparatorHeight() : 0.0;
}

- (BOOL)shouldAnimatePressWhenHighlighted {
    return YES;
}

@end

NS_ASSUME_NONNULL_END

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

CGFloat const DW_FORM_CELL_TWOLINE_VERTICAL_PADDING = 16.0;
CGFloat const DW_FORM_CELL_TWOLINE_CONTENT_VERTICAL_SPACING = 8.0;

static CGFloat const CORNER_RADIUS = 8.0;
static CGFloat const CONTENT_VERTICAL_PADDING = 5.0;

@implementation DWBaseFormTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(nullable NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];
        self.contentView.backgroundColor = self.backgroundColor;

        self.selectionStyle = UITableViewCellSelectionStyleNone;

        UIView *contentView = self.contentView;

        DWShadowView *shadowView = [[DWShadowView alloc] initWithFrame:CGRectZero];
        shadowView.translatesAutoresizingMaskIntoConstraints = NO;
        [contentView addSubview:shadowView];

        UIView *roundedContentView = [[UIView alloc] initWithFrame:CGRectZero];
        roundedContentView.translatesAutoresizingMaskIntoConstraints = NO;
        roundedContentView.backgroundColor = [UIColor dw_backgroundColor];
        roundedContentView.layer.cornerRadius = CORNER_RADIUS;
        roundedContentView.layer.masksToBounds = YES;
        roundedContentView.layer.rasterizationScale = [UIScreen mainScreen].scale;
        roundedContentView.layer.shouldRasterize = YES;
        [shadowView addSubview:roundedContentView];
        _roundedContentView = roundedContentView;

        UILayoutGuide *margins = contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [shadowView.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                 constant:CONTENT_VERTICAL_PADDING],
            [shadowView.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
            [shadowView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor
                                                    constant:-CONTENT_VERTICAL_PADDING],
            [shadowView.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],

            [roundedContentView.topAnchor constraintEqualToAnchor:shadowView.topAnchor],
            [roundedContentView.leadingAnchor constraintEqualToAnchor:shadowView.leadingAnchor],
            [roundedContentView.bottomAnchor constraintEqualToAnchor:shadowView.bottomAnchor],
            [roundedContentView.trailingAnchor constraintEqualToAnchor:shadowView.trailingAnchor],
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

- (BOOL)shouldAnimatePressWhenHighlighted {
    return YES;
}

@end

NS_ASSUME_NONNULL_END

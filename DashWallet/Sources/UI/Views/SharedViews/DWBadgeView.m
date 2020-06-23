//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWBadgeView.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWBadgeView ()

@property (readonly, nonatomic, strong) UILabel *label;

@end

NS_ASSUME_NONNULL_END

@implementation DWBadgeView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setup_badgeView];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setup_badgeView];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.layer.cornerRadius = floor(CGRectGetHeight(self.bounds) / 2.0);
}

- (void)setBackgroundColor:(UIColor *)backgroundColor {
    [super setBackgroundColor:backgroundColor];

    self.label.backgroundColor = backgroundColor;
}

- (NSString *)text {
    return self.label.text;
}

- (void)setText:(NSString *)text {
    self.label.text = text;
    [self invalidateIntrinsicContentSize];
}

- (UIFont *)font {
    return self.label.font;
}

- (void)setFont:(UIFont *)font {
    self.label.font = font;
}

- (UIColor *)textColor {
    return self.label.textColor;
}

- (void)setTextColor:(UIColor *)textColor {
    self.label.textColor = textColor;
}

#pragma mark - Private

- (void)setup_badgeView {
    self.backgroundColor = [UIColor dw_tintColor];

    self.layer.masksToBounds = YES;

    self.userInteractionEnabled = NO;

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.backgroundColor = self.backgroundColor;
    label.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = [UIColor dw_dashBlueColor];
    label.textAlignment = NSTextAlignmentCenter;
    [self addSubview:label];
    _label = label;

    const CGFloat verticalPadding = 5.0;
    const CGFloat horizontalPadding = 14.0;

    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:self.topAnchor
                                        constant:verticalPadding],
        [label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                            constant:horizontalPadding],
        [self.bottomAnchor constraintEqualToAnchor:label.bottomAnchor
                                          constant:verticalPadding],
        [self.trailingAnchor constraintEqualToAnchor:label.trailingAnchor
                                            constant:horizontalPadding],
    ]];
}

@end

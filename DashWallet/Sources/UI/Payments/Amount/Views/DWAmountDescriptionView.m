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

#import "DWAmountDescriptionView.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const SEPARATOR_HEIGHT = 1.0;
static CGFloat const PADDING = 16.0;

static CALayer *SeparatorLineLayer(void) {
    CALayer *layer = [CALayer layer];
    layer.backgroundColor = [UIColor dw_separatorLineColor].CGColor;
    return layer;
}

@interface DWAmountDescriptionView ()

@property (nonatomic, strong) CALayer *topLineLayer;
@property (nonatomic, strong) UILabel *descriptionLabel;

@end

@implementation DWAmountDescriptionView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

        _topLineLayer = SeparatorLineLayer();
        [self.layer addSublayer:_topLineLayer];

        UILabel *descriptionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        descriptionLabel.backgroundColor = self.backgroundColor;
        descriptionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
        descriptionLabel.adjustsFontForContentSizeCategory = YES;
        descriptionLabel.numberOfLines = 0;
        descriptionLabel.lineBreakMode = NSLineBreakByWordWrapping;
        descriptionLabel.textAlignment = NSTextAlignmentCenter;
        descriptionLabel.adjustsFontSizeToFitWidth = YES;
        descriptionLabel.minimumScaleFactor = 0.5;
        [self addSubview:descriptionLabel];
        _descriptionLabel = descriptionLabel;

        [NSLayoutConstraint activateConstraints:@[
            [descriptionLabel.topAnchor constraintEqualToAnchor:self.topAnchor
                                                       constant:PADDING],
            [descriptionLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [descriptionLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor
                                                          constant:-PADDING],
            [descriptionLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    const CGSize size = self.bounds.size;
    self.topLineLayer.frame = CGRectMake(0.0, 0.0, size.width, SEPARATOR_HEIGHT);
}

- (nullable NSString *)text {
    return self.descriptionLabel.text;
}

- (void)setText:(nullable NSString *)text {
    self.descriptionLabel.text = text;
    [self invalidateIntrinsicContentSize];
}

@end

NS_ASSUME_NONNULL_END

//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import "DWExploreButton.h"

#import "DWUIKit.h"
#import "UIView+DWAnimations.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWExploreButton ()

@property (readonly, nonatomic, strong) UIImageView *iconImageView;
@property (readonly, nonatomic, strong) UILabel *textLabel;

@end

NS_ASSUME_NONNULL_END

@implementation DWExploreButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIImageView *iconImageView = [[UIImageView alloc] init];
        iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:iconImageView];
        _iconImageView = iconImageView;

        UILabel *textLabel = [[UILabel alloc] init];
        textLabel.translatesAutoresizingMaskIntoConstraints = NO;
        textLabel.numberOfLines = 0;
        [self addSubview:textLabel];
        _textLabel = textLabel;

        [NSLayoutConstraint activateConstraints:@[
            [iconImageView.topAnchor constraintEqualToAnchor:self.topAnchor
                                                    constant:14],
            [iconImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                        constant:15],
            [iconImageView.widthAnchor constraintEqualToConstant:34],
            [iconImageView.heightAnchor constraintEqualToConstant:34],

            [textLabel.topAnchor constraintEqualToAnchor:self.topAnchor
                                                constant:12],
            [textLabel.leadingAnchor constraintEqualToAnchor:iconImageView.trailingAnchor
                                                    constant:10],
            [self.trailingAnchor constraintEqualToAnchor:textLabel.trailingAnchor
                                                constant:15],
            [self.bottomAnchor constraintEqualToAnchor:textLabel.bottomAnchor
                                              constant:12],
        ]];
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];

    [self dw_pressedAnimation:DWPressedAnimationStrength_Medium pressed:highlighted];
}

- (void)setImage:(UIImage *)image title:(NSString *)title subtitle:(NSString *)subtitle {
    self.iconImageView.image = image;

    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];
    [text beginEditing];

    [text appendAttributedString:
              [[NSAttributedString alloc]
                  initWithString:[title stringByAppendingString:@"\n"]
                      attributes:@{
                          NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline],
                          NSForegroundColorAttributeName : [UIColor dw_darkTitleColor],
                      }]];

    [text appendAttributedString:
              [[NSAttributedString alloc]
                  initWithString:subtitle
                      attributes:@{
                          NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1],
                          NSForegroundColorAttributeName : [UIColor dw_tertiaryTextColor],
                      }]];

    [text endEditing];
    self.textLabel.attributedText = text;
}

@end

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

#import "DWInfoPopupContentView.h"

#import "DWUIKit.h"

@interface DWInfoPopupTextView : UIView

@property (readonly, nonatomic, strong) UILabel *textLabel;

@end

@implementation DWInfoPopupTextView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];
        self.layer.cornerRadius = 8.0;
        self.layer.masksToBounds = YES;

        UILabel *textLabel = [[UILabel alloc] init];
        textLabel.translatesAutoresizingMaskIntoConstraints = NO;
        textLabel.textColor = [UIColor dw_darkTitleColor];
        textLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];
        textLabel.numberOfLines = 0;
        [self addSubview:textLabel];
        _textLabel = textLabel;

        UIImageView *crossImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"payments_nav_cross"]];
        crossImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:crossImageView];

        [NSLayoutConstraint activateConstraints:@[
            [crossImageView.topAnchor constraintEqualToAnchor:self.topAnchor
                                                     constant:12.0],
            [self.trailingAnchor constraintEqualToAnchor:crossImageView.trailingAnchor
                                                constant:12.0],

            [textLabel.topAnchor constraintEqualToAnchor:self.topAnchor
                                                constant:22.0],
            [textLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                    constant:22.0],
            [self.bottomAnchor constraintEqualToAnchor:textLabel.bottomAnchor
                                              constant:22.0],
            [self.trailingAnchor constraintEqualToAnchor:textLabel.trailingAnchor
                                                constant:44.0],
        ]];
    }
    return self;
}

@end

#pragma mark -

@interface DWInfoPopupContentView ()

@property (readonly, nonatomic, strong) UIImageView *iconImageView;
@property (readonly, nonatomic, strong) UIImageView *arrowImageView;
@property (readonly, nonatomic, strong) DWInfoPopupTextView *textView;

@property (nonatomic, assign) BOOL isArrowRotated;

@end

@implementation DWInfoPopupContentView

- (NSString *)text {
    return self.textView.textLabel.text;
}

- (void)setText:(NSString *)text {
    self.textView.textLabel.text = text;
    [self setNeedsLayout];
}

- (void)setPointerOffset:(CGPoint)pointerOffset {
    _pointerOffset = pointerOffset;
    [self setNeedsLayout];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];

        UIImageView *iconImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"icon_info"]];
        [self addSubview:iconImageView];
        _iconImageView = iconImageView;

        UIImageView *arrowImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"info_triangle"]];
        [self addSubview:arrowImageView];
        _arrowImageView = arrowImageView;

        DWInfoPopupTextView *textView = [[DWInfoPopupTextView alloc] initWithFrame:CGRectMake(0, 0, 200, 80)];
        [self addSubview:textView];
        _textView = textView;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    const CGSize size = self.bounds.size;
    const CGFloat padding = IS_IPAD ? 100.0 : 30.0;
    const CGFloat contentWidth = size.width - padding * 2;

    const CGSize textSize = [self.textView systemLayoutSizeFittingSize:CGSizeMake(contentWidth, UILayoutFittingExpandedSize.height)
                                         withHorizontalFittingPriority:UILayoutPriorityRequired
                                               verticalFittingPriority:UILayoutPriorityFittingSizeLevel];

    const BOOL hideArrow = textSize.height > size.height / 2.0;
    self.iconImageView.hidden = hideArrow;
    self.arrowImageView.hidden = hideArrow;

    if (hideArrow) {
        self.textView.frame = CGRectMake(padding, (size.height - textSize.height) / 2.0, textSize.width, textSize.height);
    }
    else {
        const CGSize iconSize = self.iconImageView.image.size;
        const CGSize arrowSize = self.arrowImageView.image.size;
        const CGFloat spacing = 4.0;

        const CGFloat contentHeight = iconSize.height + spacing + arrowSize.height + textSize.height;
        const BOOL rotated = (self.pointerOffset.y + contentHeight) > size.height;
        if (rotated) {
            self.arrowImageView.transform = CGAffineTransformMakeRotation(M_PI);

            CGFloat top = self.pointerOffset.y;
            self.iconImageView.frame = CGRectMake(self.pointerOffset.x, top, iconSize.width, iconSize.height);
            top -= iconSize.height + spacing;

            self.arrowImageView.frame = CGRectMake(self.pointerOffset.x, top, arrowSize.width, arrowSize.height);

            top -= textSize.height;
            self.textView.frame = CGRectMake(padding, top, textSize.width, textSize.height);
        }
        else {
            self.arrowImageView.transform = CGAffineTransformIdentity;

            CGFloat top = self.pointerOffset.y;
            self.iconImageView.frame = CGRectMake(self.pointerOffset.x, top, iconSize.width, iconSize.height);
            top += iconSize.height + spacing;

            self.arrowImageView.frame = CGRectMake(self.pointerOffset.x, top, arrowSize.width, arrowSize.height);
            top += arrowSize.height;

            self.textView.frame = CGRectMake(padding, top, textSize.width, textSize.height);
        }
    }
}

@end

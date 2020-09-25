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

#import "DWAvatarEditSelectorContentView.h"

#import "DWPressableButton.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWAvatarEditSelectorContentView ()

@end

NS_ASSUME_NONNULL_END

@implementation DWAvatarEditSelectorContentView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_backgroundColor];

        self.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        self.layer.cornerRadius = 8.0;
        self.layer.masksToBounds = YES;

        UIButton *photoButton = [self.class button];
        [photoButton setImage:[UIImage imageNamed:@"dp_avatar_photo"] forState:UIControlStateNormal];
        [photoButton setTitle:NSLocalizedString(@"Take a Photo from Camera", nil) forState:UIControlStateNormal];
        [photoButton addTarget:self action:@selector(photoButtonAction:) forControlEvents:UIControlEventTouchUpInside];

        UIButton *galleryButton = [self.class button];
        [galleryButton setImage:[UIImage imageNamed:@"dp_avatar_gallery"] forState:UIControlStateNormal];
        [galleryButton setTitle:NSLocalizedString(@"Select from Gallery", nil) forState:UIControlStateNormal];
        [galleryButton addTarget:self action:@selector(galleryButtonAction:) forControlEvents:UIControlEventTouchUpInside];

        UIView *separator = [[UIView alloc] init];
        separator.translatesAutoresizingMaskIntoConstraints = NO;
        separator.backgroundColor = [UIColor dw_separatorLineColor];

        UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ photoButton, separator, galleryButton ]];
        stackView.translatesAutoresizingMaskIntoConstraints = NO;
        stackView.axis = UILayoutConstraintAxisVertical;
        [self addSubview:stackView];

        const CGFloat padding = 16.0;
        [NSLayoutConstraint activateConstraints:@[
            [stackView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                    constant:padding],
            [self.trailingAnchor constraintEqualToAnchor:stackView.trailingAnchor
                                                constant:padding],
            [self.bottomAnchor constraintEqualToAnchor:stackView.bottomAnchor],

            [photoButton.heightAnchor constraintGreaterThanOrEqualToConstant:80],
            [galleryButton.heightAnchor constraintGreaterThanOrEqualToConstant:80],
            [separator.heightAnchor constraintEqualToConstant:1],
        ]];
    }
    return self;
}

- (void)photoButtonAction:(UIButton *)sender {
    [self.delegate avatarEditSelectorContentView:self photoButtonAction:sender];
}

- (void)galleryButtonAction:(UIButton *)sender {
    [self.delegate avatarEditSelectorContentView:self galleryButtonAction:sender];
}

+ (UIButton *)button {
    DWPressableButton *button = [[DWPressableButton alloc] initWithFrame:CGRectZero];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
    button.adjustsImageWhenHighlighted = NO;
    [button setTitleColor:[UIColor dw_darkTitleColor] forState:UIControlStateNormal];
    [button setInsetsForContentPadding:UIEdgeInsetsMake(20, 20, 20, 20) imageTitlePadding:30];
    return button;
}

@end

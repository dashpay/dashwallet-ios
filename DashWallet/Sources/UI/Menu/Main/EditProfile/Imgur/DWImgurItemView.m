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

#import "DWImgurItemView.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWImgurItemView ()

@property (readonly, nonatomic, strong) UILabel *label;

@end

NS_ASSUME_NONNULL_END

@implementation DWImgurItemView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UILabel *label = [[UILabel alloc] init];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.textColor = [UIColor dw_darkTitleColor];
        label.numberOfLines = 0;
        label.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
        [self addSubview:label];
        _label = label;

        UIImageView *imageView = [[UIImageView alloc] init];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        imageView.image = [UIImage imageNamed:@"icon_info"];
        [self addSubview:imageView];

        [NSLayoutConstraint activateConstraints:@[
            [imageView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [imageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [imageView.widthAnchor constraintEqualToConstant:20.0],
            [imageView.heightAnchor constraintEqualToConstant:20.0],

            [label.leadingAnchor constraintEqualToAnchor:imageView.trailingAnchor
                                                constant:12.0],
            [label.topAnchor constraintEqualToAnchor:self.topAnchor],
            [self.trailingAnchor constraintEqualToAnchor:label.trailingAnchor],
            [self.bottomAnchor constraintEqualToAnchor:label.bottomAnchor],
        ]];
    }
    return self;
}

- (NSAttributedString *)text {
    return self.label.attributedText;
}

- (void)setText:(NSAttributedString *)text {
    self.label.attributedText = text;
}

@end

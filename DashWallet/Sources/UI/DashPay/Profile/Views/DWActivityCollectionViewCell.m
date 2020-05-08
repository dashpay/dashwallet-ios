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

#import "DWActivityCollectionViewCell.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWActivityCollectionViewCell ()

@property (readonly, nonatomic, strong) UILabel *titleLabel;

@end

NS_ASSUME_NONNULL_END

@implementation DWActivityCollectionViewCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

        UIView *rootView = [[UIView alloc] init];
        rootView.translatesAutoresizingMaskIntoConstraints = NO;
        rootView.backgroundColor = self.backgroundColor;
        [self.contentView addSubview:rootView];
        _rootView = rootView;

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.backgroundColor = self.backgroundColor;
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
        titleLabel.adjustsFontForContentSizeCategory = YES;
        titleLabel.numberOfLines = 0;
        [rootView addSubview:titleLabel];
        _titleLabel = titleLabel;

        UILayoutGuide *guide = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [rootView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [rootView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [guide.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor],
            [self.contentView.bottomAnchor constraintEqualToAnchor:rootView.bottomAnchor],

            [titleLabel.topAnchor constraintEqualToAnchor:rootView.topAnchor
                                                 constant:16.0],
            [titleLabel.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor],
            [rootView.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
            [rootView.bottomAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                                  constant:16.0],
        ]];
    }
    return self;
}

- (void)setText:(NSString *)text {
    _text = [text copy];
    self.titleLabel.text = text;
}

@end

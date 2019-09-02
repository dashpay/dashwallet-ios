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

#import "DWPinInputStepView.h"

#import "DWPinField.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const VERTICAL_PADDING = 16.0;

@interface DWPinInputStepView ()

@property (readonly, nonatomic, strong) UILabel *titleLabel;

@end

@implementation DWPinInputStepView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.adjustsFontForContentSizeCategory = YES;
        titleLabel.numberOfLines = 0;
        titleLabel.backgroundColor = self.backgroundColor;
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle2];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.adjustsFontSizeToFitWidth = YES;
        titleLabel.minimumScaleFactor = 0.5;
        [self addSubview:titleLabel];
        _titleLabel = titleLabel;

        DWPinField *inputView = [[DWPinField alloc] initWithStyle:DSPinFieldStyle_Default];
        inputView.backgroundColor = self.backgroundColor;
        inputView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:inputView];
        _pinField = inputView;

        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
            [titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [inputView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [inputView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                                constant:VERTICAL_PADDING],
            [inputView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (nullable NSString *)titleText {
    return self.titleLabel.text;
}

- (void)setTitleText:(nullable NSString *)titleText {
    self.titleLabel.text = titleText;
}

@end

NS_ASSUME_NONNULL_END

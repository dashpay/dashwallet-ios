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

#import "DWNetworkUnavailableView.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWNetworkUnavailableView ()

@property (readonly, strong, nonatomic) UILabel *textLabel;

@end

NS_ASSUME_NONNULL_END

@implementation DWNetworkUnavailableView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIImageView *imageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"network_unavailable"]];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:imageView];

        UILabel *textLabel = [[UILabel alloc] init];
        textLabel.translatesAutoresizingMaskIntoConstraints = NO;
        textLabel.textAlignment = NSTextAlignmentCenter;
        textLabel.numberOfLines = 0;
        [self addSubview:textLabel];
        _textLabel = textLabel;

        [NSLayoutConstraint activateConstraints:@[
            [imageView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [imageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],

            [textLabel.topAnchor constraintEqualToAnchor:imageView.bottomAnchor
                                                constant:12.0],
            [textLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.trailingAnchor constraintEqualToAnchor:textLabel.trailingAnchor],
            [self.bottomAnchor constraintEqualToAnchor:textLabel.bottomAnchor],
        ]];
    }
    return self;
}

- (void)setError:(NSString *)error {
    _error = error;

    NSMutableAttributedString *string = [[NSMutableAttributedString alloc] init];
    [string beginEditing];

    [string appendAttributedString:
                [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Network Unavailable", nil)
                                                attributes:@{
                                                    NSForegroundColorAttributeName : [UIColor dw_darkTitleColor],
                                                    NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline],
                                                }]];

    [string appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];

    [string appendAttributedString:
                [[NSAttributedString alloc] initWithString:error
                                                attributes:@{
                                                    NSForegroundColorAttributeName : [UIColor dw_secondaryTextColor],
                                                    NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleCallout],
                                                }]];

    [string endEditing];

    self.textLabel.attributedText = string;
}

@end

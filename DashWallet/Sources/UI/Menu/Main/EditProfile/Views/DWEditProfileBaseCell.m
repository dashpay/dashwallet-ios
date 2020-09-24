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

#import "DWEditProfileBaseCell.h"

#import "DWShadowView.h"
#import "DWUIKit.h"


NS_ASSUME_NONNULL_BEGIN

@interface DWEditProfileBaseCell ()


@end

NS_ASSUME_NONNULL_END

@implementation DWEditProfileBaseCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
        titleLabel.textColor = [UIColor dw_secondaryTextColor];
        titleLabel.numberOfLines = 0;
        titleLabel.adjustsFontSizeToFitWidth = YES;
        [self.contentView addSubview:titleLabel];
        _titleLabel = titleLabel;

        DWShadowView *shadowView = [[DWShadowView alloc] initWithFrame:CGRectZero];
        shadowView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:shadowView];

        UIView *inputContentView = [[UIView alloc] initWithFrame:CGRectZero];
        inputContentView.translatesAutoresizingMaskIntoConstraints = NO;
        inputContentView.backgroundColor = [UIColor dw_backgroundColor];
        inputContentView.layer.cornerRadius = 8.0;
        inputContentView.layer.masksToBounds = YES;
        [shadowView addSubview:inputContentView];
        _inputContentView = inputContentView;

        UILabel *validationLabel = [[UILabel alloc] init];
        validationLabel.translatesAutoresizingMaskIntoConstraints = NO;
        validationLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
        validationLabel.textColor = [UIColor dw_secondaryTextColor];
        validationLabel.numberOfLines = 0;
        validationLabel.adjustsFontSizeToFitWidth = YES;
        [self.contentView addSubview:validationLabel];
        _validationLabel = validationLabel;

        const CGFloat verticalPadding = 5.0;

        UILayoutGuide *guide = self.contentView.layoutMarginsGuide;
        const CGFloat spacing = 16.0;
        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor
                                                 constant:verticalPadding],
            [titleLabel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [guide.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

            [shadowView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                                 constant:spacing],
            [shadowView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [guide.trailingAnchor constraintEqualToAnchor:shadowView.trailingAnchor],

            [validationLabel.topAnchor constraintEqualToAnchor:shadowView.bottomAnchor
                                                      constant:spacing],
            [validationLabel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [guide.trailingAnchor constraintEqualToAnchor:validationLabel.trailingAnchor],
            [self.contentView.bottomAnchor constraintEqualToAnchor:validationLabel.bottomAnchor
                                                          constant:verticalPadding],

            [inputContentView.topAnchor constraintEqualToAnchor:shadowView.topAnchor],
            [inputContentView.leadingAnchor constraintEqualToAnchor:shadowView.leadingAnchor],
            [shadowView.trailingAnchor constraintEqualToAnchor:inputContentView.trailingAnchor],
            [shadowView.bottomAnchor constraintEqualToAnchor:inputContentView.bottomAnchor],
        ]];
    }
    return self;
}

- (void)showValidationResult:(DWTextFieldFormValidationResult *)validationResult {
    self.validationLabel.textColor = validationResult.isErrored ? [UIColor dw_redColor] : [UIColor dw_secondaryTextColor];
    self.validationLabel.text = validationResult.info;
}

@end

//
//  Created by Sam Westrich
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

#import "DWPublicKeyGenerationTableViewCell.h"
#import "DWSharedUIConstants.h"
#import "DWUIKit.h"
#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWPublicKeyGenerationTableViewCell ()

@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) UITextField *publicKeyTextField;
@property (readonly, nonatomic, strong) UITextField *indexTextField;

@end

@implementation DWPublicKeyGenerationTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(nullable NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        UIView *contentView = self.roundedContentView;
        NSParameterAssert(contentView);

        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.backgroundColor = [UIColor dw_backgroundColor];
        titleLabel.textColor = [UIColor dw_darkTitleColor];
        titleLabel.numberOfLines = 0;
        titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
        titleLabel.adjustsFontForContentSizeCategory = YES;
        titleLabel.minimumScaleFactor = 0.5;
        titleLabel.adjustsFontSizeToFitWidth = YES;
        [titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                    forAxis:UILayoutConstraintAxisVertical];
        [contentView addSubview:titleLabel];
        _titleLabel = titleLabel;

        UITextField *publicKeyTextField = [[UITextField alloc] initWithFrame:CGRectZero];
        publicKeyTextField.translatesAutoresizingMaskIntoConstraints = NO;
        publicKeyTextField.backgroundColor = [UIColor dw_backgroundColor];
        publicKeyTextField.textColor = [UIColor dw_darkTitleColor];
        publicKeyTextField.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
        publicKeyTextField.delegate = self;
        [contentView addSubview:publicKeyTextField];
        _publicKeyTextField = publicKeyTextField;

        const CGFloat margin = DWDefaultMargin();
        const CGFloat padding = DW_FORM_CELL_VERTICAL_PADDING;

        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                 constant:padding],
            [titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                     constant:margin],
            [titleLabel.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor
                                                    constant:-padding],

            [publicKeyTextField.leadingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor
                                                             constant:DW_FORM_CELL_SPACING],
            [publicKeyTextField.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor
                                                              constant:-margin],
            [publicKeyTextField.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],
        ]];

        [self setupObserving];
    }

    return self;
}
- (void)setupObserving {
    [self mvvm_observe:DW_KEYPATH(self, cellModel.title)
                  with:^(__typeof(self) self, NSString *value) {
                      self.titleLabel.text = value ?: @" ";
                  }];

    [self mvvm_observe:DW_KEYPATH(self, cellModel.publicKeyData)
                  with:^(__typeof(self) self, NSData *value) {
                      [self.publicKeyTextField setText:value.hexString];
                  }];
}

- (BOOL)shouldAnimatePressWhenHighlighted {
    return NO;
}

#pragma mark - Private

- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (textField && [textField isEqual:_publicKeyTextField]) {
        self.cellModel.publicKeyData = [textField.text hexToData];
    }
    else {
    }
}

@end

NS_ASSUME_NONNULL_END

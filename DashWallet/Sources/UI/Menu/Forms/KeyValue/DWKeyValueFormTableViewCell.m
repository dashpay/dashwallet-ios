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

#import "DWKeyValueFormTableViewCell.h"

#import "DWSharedUIConstants.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGSize const ACCESSORY_SIZE = {26.0, 26.0};

@interface DWKeyValueFormTableViewCell ()

@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) UILabel *actionLabel;
@property (readonly, nonatomic, strong) UITextField *valueTextField;

@end

@implementation DWKeyValueFormTableViewCell

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

        UITextField *valueTextField = [[UITextField alloc] initWithFrame:CGRectZero];
        valueTextField.translatesAutoresizingMaskIntoConstraints = NO;
        valueTextField.backgroundColor = [UIColor dw_backgroundColor];
        valueTextField.textColor = [UIColor dw_tertiaryTextColor];
        valueTextField.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
        valueTextField.delegate = self;
        [contentView addSubview:valueTextField];
        _valueTextField = valueTextField;

        UILabel *actionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        actionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        actionLabel.backgroundColor = [UIColor dw_backgroundColor];
        actionLabel.textAlignment = NSTextAlignmentRight;
        actionLabel.textColor = [UIColor dw_dashBlueColor];
        actionLabel.numberOfLines = 0;
        actionLabel.lineBreakMode = NSLineBreakByWordWrapping;
        actionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
        actionLabel.adjustsFontForContentSizeCategory = YES;
        actionLabel.minimumScaleFactor = 0.5;
        actionLabel.adjustsFontSizeToFitWidth = YES;
        [actionLabel setContentCompressionResistancePriority:UILayoutPriorityRequired - 1
                                                     forAxis:UILayoutConstraintAxisHorizontal];
        [actionLabel setContentCompressionResistancePriority:UILayoutPriorityRequired - 1
                                                     forAxis:UILayoutConstraintAxisVertical];
        [actionLabel setContentHuggingPriority:UILayoutPriorityDefaultLow - 1
                                       forAxis:UILayoutConstraintAxisHorizontal];
        [contentView addSubview:actionLabel];
        _actionLabel = actionLabel;

        const CGFloat margin = DWDefaultMargin();
        const CGFloat padding = DW_FORM_CELL_TWOLINE_VERTICAL_PADDING;

        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                                 constant:padding],
            [titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                     constant:margin],

            [valueTextField.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                                     constant:DW_FORM_CELL_TWOLINE_CONTENT_VERTICAL_SPACING - 4],
            [valueTextField.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                                         constant:margin],
            [valueTextField.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor
                                                        constant:-padding],
            [valueTextField.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor
                                                          constant:-margin],

            [actionLabel.topAnchor constraintEqualToAnchor:titleLabel.topAnchor
                                                  constant:0],
            [actionLabel.leadingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor
                                                      constant:DW_FORM_CELL_SPACING],
            [actionLabel.bottomAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                                     constant:0],
            [actionLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor
                                                       constant:-margin],

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

    [self mvvm_observe:DW_KEYPATH(self, cellModel.valueText)
                  with:^(__typeof(self) self, NSString *value) {
                      [self.valueTextField setText:value];
                  }];

    [self mvvm_observe:DW_KEYPATH(self, cellModel.actionText)
                  with:^(__typeof(self) self, NSAttributedString *value) {
                      [self.actionLabel setAttributedText:value];
                  }];
}

- (void)setCellModel:(nullable DWKeyValueFormCellModel *)cellModel {
    _cellModel = cellModel;
    if (cellModel.placeholderText) {
        [self.valueTextField setPlaceholder:cellModel.placeholderText];
    }
    if (cellModel.actionText) {
        [self.actionLabel setAttributedText:cellModel.actionText];
    }
    if (!cellModel.editable) {
        [self.valueTextField setUserInteractionEnabled:FALSE];
    }
}

- (BOOL)shouldAnimatePressWhenHighlighted {
    return NO;
}

#pragma mark - Private

- (void)textFieldDidEndEditing:(UITextField *)textField {
    self.cellModel.valueText = textField.text;
}

- (BOOL)resignFirstResponder {
    BOOL resigned = [super resignFirstResponder];
    if ([self.valueTextField isFirstResponder]) {
        resigned |= [self.valueTextField resignFirstResponder];
    }
    return resigned;
}

@end

NS_ASSUME_NONNULL_END

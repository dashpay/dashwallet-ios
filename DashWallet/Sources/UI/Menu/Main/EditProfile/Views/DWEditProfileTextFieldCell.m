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

#import "DWEditProfileTextFieldCell.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWEditProfileTextFieldCell () <UITextFieldDelegate>

@property (readonly, nonatomic, strong) UITextField *textField;

@end

NS_ASSUME_NONNULL_END

@implementation DWEditProfileTextFieldCell


- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        UITextField *textField = [[UITextField alloc] initWithFrame:CGRectZero];
        textField.translatesAutoresizingMaskIntoConstraints = NO;
        textField.backgroundColor = [UIColor dw_backgroundColor];
        textField.font = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
        textField.adjustsFontSizeToFitWidth = YES;
        textField.textColor = [UIColor dw_darkTitleColor];
        textField.delegate = self;
        [self.inputContentView addSubview:textField];
        _textField = textField;

        const CGFloat padding = 20.0;
        const CGFloat verticalPadding = 5.0;
        [NSLayoutConstraint activateConstraints:@[
            [textField.topAnchor constraintEqualToAnchor:self.inputContentView.topAnchor
                                                constant:verticalPadding],
            [textField.leadingAnchor constraintEqualToAnchor:self.inputContentView.leadingAnchor
                                                    constant:padding],
            [self.inputContentView.trailingAnchor constraintEqualToAnchor:textField.trailingAnchor
                                                                 constant:padding],
            [self.inputContentView.bottomAnchor constraintEqualToAnchor:textField.bottomAnchor
                                                               constant:verticalPadding],

            [textField.heightAnchor constraintEqualToConstant:40],
        ]];

        [self mvvm_observe:@"cellModel.title"
                      with:^(typeof(self) self, NSString *value) {
                          self.titleLabel.text = value;
                      }];

        [self mvvm_observe:@"cellModel.placeholder"
                      with:^(typeof(self) self, NSString *value) {
                          self.textField.placeholder = value;
                      }];

        [self mvvm_observe:@"cellModel.text"
                      with:^(typeof(self) self, NSString *value) {
                          self.textField.text = value;

                          [self provideValidationResult:[self.cellModel postValidate]];
                      }];
    }
    return self;
}

- (BOOL)isFirstResponder {
    return self.textField.isFirstResponder;
}

- (void)setCellModel:(nullable DWTextFieldFormCellModel *)cellModel {
    _cellModel = cellModel;

    self.textField.autocapitalizationType = cellModel.autocapitalizationType;
    self.textField.autocorrectionType = cellModel.autocorrectionType;
    self.textField.keyboardType = cellModel.keyboardType;
    self.textField.returnKeyType = cellModel.returnKeyType;
    self.textField.enablesReturnKeyAutomatically = cellModel.enablesReturnKeyAutomatically;
    self.textField.secureTextEntry = cellModel.secureTextEntry;

    [self provideValidationResult:[cellModel postValidate]];
}

#pragma mark - TextInputFormTableViewCell

- (void)textInputBecomeFirstResponder {
    [self.textField becomeFirstResponder];
}


#pragma mark UITextFieldDelegate

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    [self provideValidationResult:[self.cellModel postValidate]];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    BOOL allowed = [self.cellModel validateReplacementString:string text:textField.text];
    if (!allowed) {
        return NO;
    }

    self.cellModel.text = [textField.text stringByReplacingCharactersInRange:range withString:string];
    if (self.cellModel.didChangeValueBlock) {
        self.cellModel.didChangeValueBlock(self.cellModel);
    }

    [self provideValidationResult:[self.cellModel postValidate]];

    return NO;
}

- (BOOL)textFieldShouldClear:(UITextField *)textField {
    self.cellModel.text = @"";
    if (self.cellModel.didChangeValueBlock) {
        self.cellModel.didChangeValueBlock(self.cellModel);
    }

    return NO;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField.returnKeyType == UIReturnKeyNext) {
        [self.delegate editProfileTextFieldCellActivateNextFirstResponder:self];
    }
    else if (textField.returnKeyType == UIReturnKeyDone) {
        [self endEditing:YES];
    }

    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField reason:(UITextFieldDidEndEditingReason)reason {
    [self provideValidationResult:[self.cellModel postValidate]];

    if (reason == UITextFieldDidEndEditingReasonCommitted && self.cellModel.didReturnValueBlock) {
        self.cellModel.didReturnValueBlock(self.cellModel);
    }
}

@end

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

#import "DWEditProfileTextViewCell.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWEditProfileTextViewCell () <UITextViewDelegate>

@property (readonly, nonatomic, strong) UITextView *textView;

@end

NS_ASSUME_NONNULL_END

@implementation DWEditProfileTextViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        UITextView *textView = [[UITextView alloc] initWithFrame:CGRectZero textContainer:nil];
        textView.translatesAutoresizingMaskIntoConstraints = NO;
        textView.textContainerInset = UIEdgeInsetsZero;
        textView.textContainer.lineFragmentPadding = 0.0;
        textView.font = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
        textView.delegate = self;
        [self.inputContentView addSubview:textView];
        _textView = textView;

        const CGFloat padding = 20.0;
        const CGFloat verticalPadding = 10.0;
        [NSLayoutConstraint activateConstraints:@[
            [textView.topAnchor constraintEqualToAnchor:self.inputContentView.topAnchor
                                               constant:verticalPadding],
            [textView.leadingAnchor constraintEqualToAnchor:self.inputContentView.leadingAnchor
                                                   constant:padding],
            [self.inputContentView.trailingAnchor constraintEqualToAnchor:textView.trailingAnchor
                                                                 constant:padding],
            [self.inputContentView.bottomAnchor constraintEqualToAnchor:textView.bottomAnchor
                                                               constant:verticalPadding],
            [textView.heightAnchor constraintEqualToConstant:125],
        ]];

        [self mvvm_observe:@"cellModel.title"
                      with:^(typeof(self) self, NSString *value) {
                          self.titleLabel.text = value;
                      }];

        [self mvvm_observe:@"cellModel.placeholder"
                      with:^(typeof(self) self, NSString *value){
                          // not supported
                      }];

        [self mvvm_observe:@"cellModel.text"
                      with:^(typeof(self) self, NSString *value) {
                          self.textView.text = value;

                          [self showValidationResult:[self.cellModel postValidate]];
                      }];
    }
    return self;
}

- (void)setCellModel:(nullable DWTextViewFormCellModel *)cellModel {
    _cellModel = cellModel;

    self.textView.autocapitalizationType = cellModel.autocapitalizationType;
    self.textView.autocorrectionType = cellModel.autocorrectionType;
    self.textView.keyboardType = cellModel.keyboardType;
    self.textView.returnKeyType = cellModel.returnKeyType;
    self.textView.enablesReturnKeyAutomatically = cellModel.enablesReturnKeyAutomatically;
    self.textView.secureTextEntry = cellModel.secureTextEntry;

    [self showValidationResult:[self.cellModel postValidate]];
}

#pragma mark - TextInputFormTableViewCell

- (void)textInputBecomeFirstResponder {
    [self.textView becomeFirstResponder];
}

#pragma mark - UITextViewDelegate

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    BOOL allowed = [self.cellModel validateReplacementString:text text:textView.text];
    if (!allowed) {
        return NO;
    }

    self.cellModel.text = [textView.text stringByReplacingCharactersInRange:range withString:text];
    if (self.cellModel.didChangeValueBlock) {
        self.cellModel.didChangeValueBlock(self.cellModel);
    }

    [self showValidationResult:[self.cellModel postValidate]];

    return NO;
}

@end

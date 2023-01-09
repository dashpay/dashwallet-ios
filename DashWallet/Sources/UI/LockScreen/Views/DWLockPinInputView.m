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

#import "DWLockPinInputView.h"

#import "DWPinField.h"
#import "DWUIKit.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const VERTICAL_PADDING = 16.0;
static CGFloat const SPACING = 8.0;

@interface DWLockPinInputView () <DSPinFieldDelegate>

@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) UILabel *attemptsLabel;
@property (readonly, nonatomic, strong) UILabel *errorLabel;
@property (readonly, nonatomic, strong) DWPinField *pinField;
@property (nullable, nonatomic, weak) NumberKeyboard *keyboard;
@property (nonatomic, strong) UINotificationFeedbackGenerator *feedbackGenerator;

@end

@implementation DWLockPinInputView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self lockPinInputView_setup];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self lockPinInputView_setup];
    }
    return self;
}

- (void)lockPinInputView_setup {
    self.backgroundColor = [UIColor clearColor];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.numberOfLines = 0;
    titleLabel.backgroundColor = self.backgroundColor;
    titleLabel.textColor = [UIColor dw_lightTitleColor];
    titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle3];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.minimumScaleFactor = 0.5;
    [self addSubview:titleLabel];
    _titleLabel = titleLabel;

    UILabel *attemptsLabel = [[UILabel alloc] init];
    attemptsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    attemptsLabel.adjustsFontForContentSizeCategory = YES;
    attemptsLabel.numberOfLines = 0;
    attemptsLabel.backgroundColor = self.backgroundColor;
    attemptsLabel.textColor = [UIColor dw_lightTitleColor];
    attemptsLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];
    attemptsLabel.textAlignment = NSTextAlignmentCenter;
    attemptsLabel.adjustsFontSizeToFitWidth = YES;
    attemptsLabel.minimumScaleFactor = 0.5;
    attemptsLabel.hidden = YES;
    _attemptsLabel = attemptsLabel;

    UILabel *errorLabel = [[UILabel alloc] init];
    errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    errorLabel.adjustsFontForContentSizeCategory = YES;
    errorLabel.numberOfLines = 0;
    errorLabel.backgroundColor = self.backgroundColor;
    errorLabel.textColor = [UIColor dw_lightTitleColor];
    errorLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
    errorLabel.textAlignment = NSTextAlignmentCenter;
    errorLabel.adjustsFontSizeToFitWidth = YES;
    errorLabel.minimumScaleFactor = 0.5;
    errorLabel.hidden = YES;
    _errorLabel = errorLabel;

    DWPinField *pinField = [[DWPinField alloc] initWithStyle:DSPinFieldStyle_DefaultWhite];
    pinField.backgroundColor = self.backgroundColor;
    pinField.translatesAutoresizingMaskIntoConstraints = NO;
    pinField.delegate = self;
    _pinField = pinField;

    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ attemptsLabel, pinField, errorLabel ]];
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    stackView.alignment = UIStackViewAlignmentCenter;
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.spacing = SPACING;
    [self addSubview:stackView];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [stackView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [stackView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                            constant:VERTICAL_PADDING],
        [stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    _feedbackGenerator = [[UINotificationFeedbackGenerator alloc] init];
    [_feedbackGenerator prepare];
}

- (void)configureWithKeyboard:(NumberKeyboard *)keyboard {
    NSParameterAssert(keyboard);

    self.keyboard = keyboard;
    self.keyboard.textInput = self.pinField;
}

- (void)activatePinField {
    [self.pinField becomeFirstResponder];
}

- (void)clearAndShakePinField {
    [self.feedbackGenerator notificationOccurred:UINotificationFeedbackTypeError];

    [self.pinField dw_shakeViewWithCompletion:^{
        [self.pinField clear];

        [self.feedbackGenerator prepare];
    }];
}

- (void)setTitleText:(nullable NSString *)title {
    self.titleLabel.text = title;
}

- (void)setAttemptsText:(nullable NSString *)attemptsText errorText:(nullable NSString *)errorText {
    self.attemptsLabel.text = attemptsText;
    self.attemptsLabel.hidden = attemptsText == nil;

    self.errorLabel.text = errorText;

    const BOOL hasError = errorText != nil;
    self.pinField.hidden = hasError;
    self.errorLabel.hidden = !hasError;
}

#pragma mark - DSPinFieldDelegate

- (void)pinFieldDidFinishInput:(DSPinField *)pinField {
    [self.delegate lockPinInputView:self didFinishInputWithText:pinField.text];
}

@end

NS_ASSUME_NONNULL_END

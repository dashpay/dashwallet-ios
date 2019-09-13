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

#import "DWNumberKeyboard.h"
#import "DWPinField.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const VERTICAL_PADDING = 16.0;

@interface DWLockPinInputView () <DSPinFieldDelegate>

@property (readonly, nonatomic, strong) DWPinField *pinField;
@property (nullable, nonatomic, weak) DWNumberKeyboard *keyboard;
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
    titleLabel.text = NSLocalizedString(@"Enter PIN", nil);
    [self addSubview:titleLabel];

    DWPinField *pinField = [[DWPinField alloc] initWithStyle:DSPinFieldStyle_DefaultWhite];
    pinField.backgroundColor = self.backgroundColor;
    pinField.translatesAutoresizingMaskIntoConstraints = NO;
    pinField.delegate = self;
    [self addSubview:pinField];
    _pinField = pinField;

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [pinField.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [pinField.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor
                                           constant:VERTICAL_PADDING],
        [pinField.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    _feedbackGenerator = [[UINotificationFeedbackGenerator alloc] init];
    [_feedbackGenerator prepare];
}

- (void)configureWithKeyboard:(DWNumberKeyboard *)keyboard {
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

#pragma mark - DSPinFieldDelegate

- (void)pinFieldDidFinishInput:(DSPinField *)pinField {
    [self.delegate lockPinInputView:self didFinishInputWithText:pinField.text];
}

@end

NS_ASSUME_NONNULL_END

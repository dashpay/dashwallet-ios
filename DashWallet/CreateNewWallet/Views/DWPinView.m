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

#import "DWPinView.h"

#import "DWAmountKeyboard.h"
#import "DWPinField.h"
#import "DWPinInputStepView.h"
#import "UIColor+DWStyle.h"
#import "UIView+DWAnimations.h"

@interface DWPinView () <DWPinFieldDelegate>

@property (nullable, nonatomic, weak) DWAmountKeyboard *keyboard;

@property (nonatomic, strong) DWPinInputStepView *setPinView;
@property (nonatomic, strong) DWPinInputStepView *confirmPinView;

@property (nonatomic, strong) NSLayoutConstraint *setPinLeadingContraint;
@property (nonatomic, strong) NSLayoutConstraint *confirmPinLeadingContraint;

@end

@implementation DWPinView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupView];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setupView];
    }
    return self;
}

- (void)setupView {
    self.backgroundColor = [UIColor dw_secondaryBackgroundColor];
    self.clipsToBounds = YES;

    DWPinInputStepView *setPinView = [[DWPinInputStepView alloc] init];
    setPinView.translatesAutoresizingMaskIntoConstraints = NO;
    setPinView.titleText = NSLocalizedString(@"Set PIN", nil);
    setPinView.pinField.delegate = self;
    [self addSubview:setPinView];
    self.setPinView = setPinView;

    DWPinInputStepView *confirmPinView = [[DWPinInputStepView alloc] init];
    confirmPinView.translatesAutoresizingMaskIntoConstraints = NO;
    confirmPinView.titleText = NSLocalizedString(@"Confirm PIN", nil);
    confirmPinView.pinField.delegate = self;
    confirmPinView.hidden = YES;
    [self addSubview:confirmPinView];
    self.confirmPinView = confirmPinView;

    [NSLayoutConstraint activateConstraints:@[
        [setPinView.topAnchor constraintEqualToAnchor:self.topAnchor],
        (self.setPinLeadingContraint = [setPinView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor]),
        [setPinView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [setPinView.widthAnchor constraintEqualToAnchor:self.widthAnchor],

        [confirmPinView.topAnchor constraintEqualToAnchor:self.topAnchor],
        (self.confirmPinLeadingContraint = [confirmPinView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor]),
        [confirmPinView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [confirmPinView.widthAnchor constraintEqualToAnchor:self.widthAnchor],
    ]];
}

- (void)configureWithKeyboard:(DWAmountKeyboard *)keyboard {
    NSParameterAssert(keyboard);
    NSAssert(self.confirmPinView.hidden, @"Keyboard should not be re-set in the middle of input");

    self.keyboard = keyboard;
    self.keyboard.textInput = self.setPinView.pinField;
}

- (void)activatePinView {
    NSAssert(self.keyboard, @"Keyboard should be configured before activation");

    if (self.confirmPinView.hidden) {
        [self.setPinView.pinField becomeFirstResponder];
    }
    else {
        [self.confirmPinView.pinField becomeFirstResponder];
    }
}

#pragma mark - DWPinFieldDelegate

- (void)pinFieldDidFinishInput:(DWPinField *)pinField {
    if (self.setPinView.pinField == pinField) {
        [self confirmPin];
    }
    else if (self.confirmPinView.pinField == pinField) {
        [self checkPins];
    }
    else {
        NSAssert(NO, @"Invalid pin field");
    }
}

#pragma mark - Private

- (void)confirmPin {
    NSAssert(self.confirmPinView.hidden, @"Confirm pin view should be hidden. Inconsistent state");

    [self.setPinView.pinField resignFirstResponder];
    self.keyboard.userInteractionEnabled = NO;

    self.keyboard.textInput = self.confirmPinView.pinField;

    CGFloat constant = CGRectGetWidth(self.bounds);
    self.confirmPinLeadingContraint.constant = constant;
    [self layoutIfNeeded];
    self.confirmPinView.hidden = NO;

    self.setPinLeadingContraint.constant = -constant;
    self.confirmPinLeadingContraint.constant = 0;

    [UIView animateWithDuration:0.35
        delay:[CATransaction animationDuration]
        usingSpringWithDamping:1.0
        initialSpringVelocity:0.0
        options:UIViewAnimationOptionCurveEaseOut
        animations:^{
            [self layoutIfNeeded];
        }
        completion:^(BOOL finished) {
            [self.confirmPinView.pinField becomeFirstResponder];
            self.keyboard.userInteractionEnabled = YES;
        }];
}

- (void)checkPins {
    [self.confirmPinView.pinField resignFirstResponder];
    self.keyboard.userInteractionEnabled = NO;

    // perform any action when input animation completes
    __weak typeof(self) weakSelf = self;
    dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)([CATransaction animationDuration] * NSEC_PER_SEC));
    dispatch_after(when, dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        NSString *firstPin = strongSelf.setPinView.pinField.text;
        NSString *secondPin = strongSelf.confirmPinView.pinField.text;

        if ([firstPin isEqualToString:secondPin]) {
            [strongSelf.delegate pinView:strongSelf didFinishWithPin:secondPin];
        }
        else {
            [strongSelf.confirmPinView.pinField dw_shakeViewWithCompletion:^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }

                [strongSelf.confirmPinView.pinField clear];

                [strongSelf.confirmPinView.pinField becomeFirstResponder];
                strongSelf.keyboard.userInteractionEnabled = YES;
            }];
        }
    });
}

@end

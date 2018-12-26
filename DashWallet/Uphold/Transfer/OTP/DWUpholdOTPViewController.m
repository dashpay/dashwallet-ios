//
//  Created by Andrew Podkovyrin
//  Copyright © 2018 Dash Core Group. All rights reserved.
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

#import "DWUpholdOTPViewController.h"

#import "UIView+DWAnimations.h"
#import <UIViewController+KeyboardAdditions.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdOTPViewController () <UITextFieldDelegate>

@property (strong, nonatomic) IBOutlet UIView *contentView;
@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UITextField *textField;
@property (strong, nonatomic) IBOutlet UIButton *cancelButton;
@property (strong, nonatomic) IBOutlet UIButton *okButton;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *contentViewCenterYConstraint;

@property (assign, nonatomic) NSInteger pasteboardChangeCount;

@end

@implementation DWUpholdOTPViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"UpholdOTPStoryboard" bundle:nil];
    DWUpholdOTPViewController *controller = [storyboard instantiateInitialViewController];
    controller.shouldDimBackground = NO;

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.titleLabel.text = NSLocalizedString(@"Enter your 2FA code below", nil);
    [self.okButton setTitle:NSLocalizedString(@"OK", nil) forState:UIControlStateNormal];
    [self.cancelButton setTitle:NSLocalizedString(@"Cancel", nil) forState:UIControlStateNormal];

    self.textField.delegate = self;

    self.pasteboardChangeCount = [UIPasteboard generalPasteboard].changeCount;
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self
                           selector:@selector(applicationDidBecomeActiveNotification:)
                               name:UIApplicationDidBecomeActiveNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(pasteboardChangedNotification:)
                               name:UIPasteboardChangedNotification
                             object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self ka_startObservingKeyboardNotifications];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self.textField resignFirstResponder];
    [self ka_stopObservingKeyboardNotifications];
}

#pragma mark - Actions

- (IBAction)okButtonAction:(id)sender {
    [self confirmOTPToken];
}

- (IBAction)cancelButtonAction:(id)sender {
    [self.delegate upholdOTPViewControllerDidCancel:self];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (string.length == 0) {
        return YES;
    }

    NSString *resultText = [textField.text stringByAppendingString:string];

    return [self isLooksLikeOTPToken:resultText];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self confirmOTPToken];

    return YES;
}

#pragma mark - Keyboard

- (void)ka_keyboardWillShowOrHideWithHeight:(CGFloat)height
                          animationDuration:(NSTimeInterval)animationDuration
                             animationCurve:(UIViewAnimationCurve)animationCurve {
    if (height > 0.0) {
        CGFloat viewHeight = CGRectGetHeight(self.view.bounds);
        CGFloat contentBottom = CGRectGetMinY(self.contentView.frame) + CGRectGetHeight(self.contentView.bounds);
        CGFloat keyboardTop = viewHeight - height;
        CGFloat space = keyboardTop - contentBottom;
        CGFloat const padding = 16.0;
        if (space >= padding) {
            self.contentViewCenterYConstraint.constant = 0.0;
        }
        else {
            self.contentViewCenterYConstraint.constant = -(padding - space);
        }
    }
    else {
        self.contentViewCenterYConstraint.constant = 0.0;
    }
}

- (void)ka_keyboardShowOrHideAnimationWithHeight:(CGFloat)height
                               animationDuration:(NSTimeInterval)animationDuration
                                  animationCurve:(UIViewAnimationCurve)animationCurve {
    [self.view layoutIfNeeded];
}

#pragma mark - Notifications

- (void)applicationDidBecomeActiveNotification:(NSNotification *)sender {
    if (self.pasteboardChangeCount != [UIPasteboard generalPasteboard].changeCount) {
        [self pasteboardChangedNotification:sender];
    }
}

- (void)pasteboardChangedNotification:(NSNotification *)sender {
    self.pasteboardChangeCount = [UIPasteboard generalPasteboard].changeCount;
    [self displayTextFieldMenuIfNeeded];
}

#pragma mark - Private

- (void)confirmOTPToken {
    if (self.textField.text.length < 1) {
        [self.textField dw_shakeView];

        return;
    }

    [self.textField resignFirstResponder];

    [self.delegate upholdOTPViewController:self didFinishWithOTPToken:self.textField.text];
}

- (BOOL)isLooksLikeOTPToken:(NSString *)inputString {
    NSCharacterSet *decimalNumbersSet = [NSCharacterSet decimalDigitCharacterSet];
    NSCharacterSet *inputStringSet = [NSCharacterSet characterSetWithCharactersInString:inputString];
    BOOL stringIsValid = [decimalNumbersSet isSupersetOfSet:inputStringSet];

    return stringIsValid;
}

- (void)displayTextFieldMenuIfNeeded {
    if (![UIPasteboard generalPasteboard].hasStrings) {
        return;
    }

    NSString *string = [UIPasteboard generalPasteboard].string;
    if (![self isLooksLikeOTPToken:string]) {
        return;
    }

    [self.textField becomeFirstResponder];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIMenuController *menu = [UIMenuController sharedMenuController];
        [menu setTargetRect:self.textField.bounds inView:self.textField];
        [menu setMenuVisible:YES animated:YES];
    });
}

@end

NS_ASSUME_NONNULL_END

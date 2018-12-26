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

#import "DWUpholdRequestTransferViewController.h"

#import "DWUpholdOTPViewController.h"
#import "DWUpholdRequestTransferModel.h"
#import "UIView+DWAnimations.h"
#import <DashSync/UIImage+DSUtils.h>
#import <UIViewController+KeyboardAdditions.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdRequestTransferViewController () <UITextFieldDelegate, DWUpholdOTPViewControllerDelegate>

@property (strong, nonatomic) IBOutlet UIView *contentView;
@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *availableLabel;
@property (strong, nonatomic) IBOutlet UITextField *textField;
@property (strong, nonatomic) IBOutlet UILabel *errorLabel;
@property (strong, nonatomic) IBOutlet UIButton *transferButton;
@property (strong, nonatomic) IBOutlet UIButton *cancelButton;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *activityIndicatorView;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *contentViewCenterYConstraint;

@property (strong, nonatomic) DWUpholdRequestTransferModel *model;

@end

@implementation DWUpholdRequestTransferViewController

+ (instancetype)controllerWithCard:(DWUpholdCardObject *)card {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"UpholdRequestTransferStoryboard" bundle:nil];
    DWUpholdRequestTransferViewController *controller = [storyboard instantiateInitialViewController];
    controller.model = [[DWUpholdRequestTransferModel alloc] initWithCard:card];

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.titleLabel.text = NSLocalizedString(@"Enter the amount to transfer below", nil);
    self.errorLabel.text = NSLocalizedString(@"Something went wrong", nil);
    [self.transferButton setTitle:NSLocalizedString(@"Transfer", nil) forState:UIControlStateNormal];
    [self.cancelButton setTitle:NSLocalizedString(@"Cancel", nil) forState:UIControlStateNormal];

    self.availableLabel.attributedText = [self.model availableDashString];

    UIImage *dashImage = [[UIImage imageNamed:@"Dash-Light"] ds_imageWithTintColor:UIColorFromRGB(0x008DE4)];
    UIImageView *dashImageView = [[UIImageView alloc] initWithImage:dashImage];
    dashImageView.contentMode = UIViewContentModeRight;
    dashImageView.frame = CGRectMake(0.0, 0.0, 26.0, 30.0);
    self.textField.leftView = dashImageView;
    self.textField.leftViewMode = UITextFieldViewModeAlways;
    self.textField.placeholder = self.model.availableString;
    self.textField.delegate = self;

    [self mvvm_observe:@"self.model.state" with:^(typeof(self) self, NSNumber * value) {
        [self updateState];
    }];
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

- (IBAction)transferButtonAction:(id)sender {
    [self performTransferWithOTPToken:nil];
}

- (IBAction)cancelButtonAction:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - DWUpholdOTPViewControllerDelegate

- (void)upholdOTPViewController:(DWUpholdOTPViewController *)controller didFinishWithOTPToken:(NSString *)otpToken {
    [controller dismissViewControllerAnimated:YES completion:nil];

    [self performTransferWithOTPToken:otpToken];
}

- (void)upholdOTPViewControllerDidCancel:(DWUpholdOTPViewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:nil];

    [self.model resetState];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    self.errorLabel.hidden = YES;

    if (string.length == 0) {
        return YES;
    }

    NSString *resultText = [textField.text stringByAppendingString:string];
    NSString *charactersSetString = @"0123456789";
    NSLocale *locale = [NSLocale currentLocale];
    NSString *decimalSeparator = locale.decimalSeparator;
    charactersSetString = [charactersSetString stringByAppendingString:decimalSeparator];

    NSCharacterSet *decimalNumbersSet = [NSCharacterSet characterSetWithCharactersInString:charactersSetString];
    NSCharacterSet *textFieldStringSet = [NSCharacterSet characterSetWithCharactersInString:resultText];

    BOOL stringIsValid = [decimalNumbersSet isSupersetOfSet:textFieldStringSet];
    if (!stringIsValid) {
        return NO;
    }

    if ([string isEqualToString:decimalSeparator] && [textField.text containsString:decimalSeparator]) {
        return NO;
    }

    if ([resultText isEqualToString:decimalSeparator]) {
        textField.text = [@"0" stringByAppendingString:decimalSeparator];
        return NO;
    }

    if (resultText.length == 2) {
        NSString *zeroAndDecimalSeparator = [@"0" stringByAppendingString:decimalSeparator];
        if ([[resultText substringToIndex:1] isEqualToString:@"0"] &&
            ![resultText isEqualToString:zeroAndDecimalSeparator]) {
            textField.text = [resultText substringWithRange:NSMakeRange(1, 1)];
            return NO;
        }
    }

    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self performTransferWithOTPToken:nil];

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

#pragma mark - Private

- (void)performTransferWithOTPToken:(nullable NSString *)otpToken {
    NSString *amountString = self.textField.text;

    DWUpholdTransferModelValidationResult validationResult = [self.model validateInput:amountString];
    if (validationResult == DWUpholdTransferModelValidationResultInvalid) {
        [self.textField dw_shakeView];

        return;
    }
    else if (validationResult == DWUpholdTransferModelValidationResultAvailableLimit) {
        [self.availableLabel dw_shakeView];

        return;
    }

    [self.textField resignFirstResponder];

    [self.model createTransactionForAmount:amountString otpToken:otpToken];
}

- (void)updateState {
    switch (self.model.state) {
        case DWUpholdRequestTransferModelStateNone: {
            self.textField.userInteractionEnabled = YES;
            self.errorLabel.hidden = YES;
            self.transferButton.hidden = NO;
            [self.activityIndicatorView stopAnimating];

            break;
        }
        case DWUpholdRequestTransferModelStateLoading: {
            self.textField.userInteractionEnabled = NO;
            self.errorLabel.hidden = YES;
            self.transferButton.hidden = YES;
            [self.activityIndicatorView startAnimating];

            break;
        }
        case DWUpholdRequestTransferModelStateSuccess: {
            self.textField.userInteractionEnabled = YES;
            self.errorLabel.hidden = YES;
            self.transferButton.hidden = NO;
            [self.activityIndicatorView stopAnimating];

            break;
        }
        case DWUpholdRequestTransferModelStateFail: {
            self.textField.userInteractionEnabled = YES;
            self.errorLabel.hidden = NO;
            self.transferButton.hidden = NO;
            [self.activityIndicatorView stopAnimating];

            break;
        }
        case DWUpholdRequestTransferModelStateOTP: {
            DWUpholdOTPViewController *controller = [DWUpholdOTPViewController controller];
            controller.delegate = self;
            [self presentViewController:controller animated:YES completion:nil];

            break;
        }
    }
}

@end

NS_ASSUME_NONNULL_END

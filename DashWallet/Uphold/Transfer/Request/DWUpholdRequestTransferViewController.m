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

#import "DWUpholdRequestTransferModel.h"
#import "UIView+DWAnimations.h"
#import <DashSync/UIImage+DSUtils.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdRequestTransferViewController () <UITextFieldDelegate>

@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *availableLabel;
@property (strong, nonatomic) IBOutlet UITextField *textField;
@property (strong, nonatomic) IBOutlet UILabel *errorLabel;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *activityIndicatorView;
@property (strong, nonatomic) DWAlertAction *transferAction;

@property (strong, nonatomic) DWUpholdRequestTransferModel *model;

@end

@implementation DWUpholdRequestTransferViewController

@synthesize providedActions = _providedActions;

+ (instancetype)controllerWithCard:(DWUpholdCardObject *)card {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"UpholdRequestTransferStoryboard" bundle:nil];
    DWUpholdRequestTransferViewController *controller = [storyboard instantiateInitialViewController];
    controller.model = [[DWUpholdRequestTransferModel alloc] initWithCard:card];

    return controller;
}

- (NSArray<DWAlertAction *> *)providedActions {
    if (!_providedActions) {
        __weak typeof(self) weakSelf = self;
        DWAlertAction *cancelAction = [DWAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:DWAlertActionStyleCancel handler:^(DWAlertAction *_Nonnull action) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf cancelButtonAction];
        }];
        DWAlertAction *transferAction = [DWAlertAction actionWithTitle:NSLocalizedString(@"Transfer", nil) style:DWAlertActionStyleDefault handler:^(DWAlertAction *_Nonnull action) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf transferButtonAction];
        }];
        self.transferAction = transferAction;
        _providedActions = @[ cancelAction, transferAction ];
    }
    return _providedActions;
}

- (DWAlertAction *)preferredAction {
    return self.transferAction;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.titleLabel.text = NSLocalizedString(@"Enter the amount to transfer below", nil);

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

#pragma mark - Actions

- (void)transferButtonAction {
    [self performTransferWithOTPToken:nil];
}

- (void)cancelButtonAction {
    [self.delegate upholdRequestTransferViewControllerDidCancel:self];
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

- (BOOL)textFieldShouldClear:(UITextField *)textField {
    self.errorLabel.hidden = YES;

    return YES;
}

#pragma mark - Private

- (void)performTransferWithOTPToken:(nullable NSString *)otpToken {
    NSString *amountString = self.textField.text;

    DWUpholdTransferModelValidationResult validationResult = [self.model validateInput:amountString];
    if (validationResult == DWUpholdTransferModelValidationResultInvalidAmount) {
        self.errorLabel.text = NSLocalizedString(@"Invalid amount", nil);
        self.errorLabel.hidden = NO;

        [self.textField dw_shakeView];

        return;
    }
    else if (validationResult == DWUpholdTransferModelValidationResultInsufficientFunds) {
        self.errorLabel.text = NSLocalizedString(@"Insufficient Funds", nil);
        self.errorLabel.hidden = NO;

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
            self.transferAction.enabled = YES;
            [self.activityIndicatorView stopAnimating];

            break;
        }
        case DWUpholdRequestTransferModelStateLoading: {
            self.textField.userInteractionEnabled = NO;
            self.errorLabel.hidden = YES;
            self.transferAction.enabled = NO;
            [self.activityIndicatorView startAnimating];

            break;
        }
        case DWUpholdRequestTransferModelStateSuccess: {
            [self.delegate upholdRequestTransferViewController:self didProduceTransaction:self.model.transaction];

            self.textField.userInteractionEnabled = YES;
            self.errorLabel.hidden = YES;
            self.transferAction.enabled = YES;
            [self.activityIndicatorView stopAnimating];

            break;
        }
        case DWUpholdRequestTransferModelStateFail: {
            self.textField.userInteractionEnabled = YES;
            self.errorLabel.text = NSLocalizedString(@"Something went wrong", nil);
            self.errorLabel.hidden = NO;
            self.transferAction.enabled = YES;
            [self.activityIndicatorView stopAnimating];

            break;
        }
        case DWUpholdRequestTransferModelStateOTP: {
            __weak typeof(self) weakSelf = self;
            [self.otpProvider requestOTPWithCompletion:^(NSString *_Nullable otpToken) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }

                if (otpToken) {
                    [strongSelf performTransferWithOTPToken:otpToken];
                }
                else {
                    [strongSelf.model resetState];
                }
            }];

            break;
        }
    }
}

@end

NS_ASSUME_NONNULL_END

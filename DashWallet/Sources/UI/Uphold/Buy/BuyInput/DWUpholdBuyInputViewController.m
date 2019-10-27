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

#import "DWUpholdBuyInputViewController.h"

#import "DWUIKit.h"
#import "DWUpholdBuyInputModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdBuyInputViewController () <UITextFieldDelegate>

@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *errorLabel;
@property (strong, nonatomic) IBOutlet UITextField *textField;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *activityIndicatorView;
@property (strong, nonatomic) DWAlertAction *buyAction;

@property (strong, nonatomic) DWUpholdBuyInputModel *model;

@end

@implementation DWUpholdBuyInputViewController

@synthesize providedActions = _providedActions;

+ (instancetype)controllerWithDashCard:(DWUpholdCardObject *)dashCard fromCard:(DWUpholdCardObject *)card {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"UpholdBuyInputStoryboard" bundle:nil];
    DWUpholdBuyInputViewController *controller = [storyboard instantiateInitialViewController];
    controller.model = [[DWUpholdBuyInputModel alloc] initWithDashCard:dashCard fromCard:card];

    return controller;
}

- (NSArray<DWAlertAction *> *)providedActions {
    if (!_providedActions) {
        __weak typeof(self) weakSelf = self;
        DWAlertAction *cancelAction = [DWAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                                               style:DWAlertActionStyleCancel
                                                             handler:^(DWAlertAction *_Nonnull action) {
                                                                 __strong typeof(weakSelf) strongSelf = weakSelf;
                                                                 if (!strongSelf) {
                                                                     return;
                                                                 }

                                                                 [strongSelf cancelButtonAction];
                                                             }];
        // TODO: localize
        DWAlertAction *buyAction = [DWAlertAction actionWithTitle:@"Buy"
                                                            style:DWAlertActionStyleDefault
                                                          handler:^(DWAlertAction *_Nonnull action) {
                                                              __strong typeof(weakSelf) strongSelf = weakSelf;
                                                              if (!strongSelf) {
                                                                  return;
                                                              }

                                                              [strongSelf transferButtonAction];
                                                          }];
        self.buyAction = buyAction;
        _providedActions = @[ cancelAction, buyAction ];
    }
    return _providedActions;
}

- (DWAlertAction *)preferredAction {
    return self.buyAction;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // TODO: localize
    self.titleLabel.text = @"Buy Dash with Debit/Credit card";

    self.textField.delegate = self;

    [self mvvm_observe:@"self.model.state"
                  with:^(typeof(self) self, NSNumber *value) {
                      [self updateState];
                  }];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.textField becomeFirstResponder];
}

#pragma mark - Actions

- (void)transferButtonAction {
    [self performBuyWithOTPToken:nil];
}

- (void)cancelButtonAction {
    [self.delegate upholdBuyInputViewControllerDidCancel:self];
}

#pragma mark - UITextFieldDelegate

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    self.errorLabel.hidden = YES;

    [self.model updateAmountWithReplacementString:string range:range];

    return NO;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self performBuyWithOTPToken:nil];

    return YES;
}

#pragma mark - Private

- (void)performBuyWithOTPToken:(nullable NSString *)otpToken {
}

- (void)updateState {
    switch (self.model.state) {
        case DWUpholdBuyInputModelStateNone: {
            self.errorLabel.hidden = YES;
            self.buyAction.enabled = YES;
            [self.activityIndicatorView stopAnimating];

            break;
        }
        case DWUpholdBuyInputModelStateLoading: {
            self.errorLabel.hidden = YES;
            self.buyAction.enabled = NO;
            [self.activityIndicatorView startAnimating];

            break;
        }
        case DWUpholdBuyInputModelStateSuccess: {
            [self.delegate upholdBuyInputViewController:self didProduceTransaction:self.model.transaction];

            self.errorLabel.hidden = YES;
            self.buyAction.enabled = YES;
            [self.activityIndicatorView stopAnimating];

            break;
        }
        case DWUpholdBuyInputModelStateFail: {
            self.errorLabel.text = NSLocalizedString(@"Something went wrong", nil);
            self.errorLabel.hidden = NO;
            self.buyAction.enabled = YES;
            [self.activityIndicatorView stopAnimating];

            break;
        }
        case DWUpholdBuyInputModelStateOTP: {
            __weak typeof(self) weakSelf = self;
            [self.otpProvider requestOTPWithCompletion:^(NSString *_Nullable otpToken) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }

                if (otpToken) {
                    [strongSelf performBuyWithOTPToken:otpToken];
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

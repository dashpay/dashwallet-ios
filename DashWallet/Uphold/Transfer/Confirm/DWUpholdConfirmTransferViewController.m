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

#import "DWUpholdConfirmTransferViewController.h"

#import "DWUpholdConfirmTransferModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdConfirmTransferViewController ()

@property (strong, nonatomic) IBOutlet UIView *contentView;
@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *amountTitleLabel;
@property (strong, nonatomic) IBOutlet UILabel *amountLabel;
@property (strong, nonatomic) IBOutlet UILabel *feeTitleLabel;
@property (strong, nonatomic) IBOutlet UILabel *feeLabel;
@property (strong, nonatomic) IBOutlet UILabel *totalTitleLabel;
@property (strong, nonatomic) IBOutlet UILabel *totalLabel;
@property (strong, nonatomic) IBOutlet UILabel *descriptionLabel;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *activityIndicatorView;
@property (strong, nonatomic) IBOutlet UIButton *confirmButton;
@property (strong, nonatomic) IBOutlet UIButton *cancelButton;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *contentViewCenterYConstraint;

@property (strong, nonatomic) DWUpholdConfirmTransferModel *model;

@end

@implementation DWUpholdConfirmTransferViewController

+ (instancetype)controllerWithCard:(DWUpholdCardObject *)card transaction:(DWUpholdTransactionObject *)transaction {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"UpholdConfirmTransferStoryboard" bundle:nil];
    DWUpholdConfirmTransferViewController *controller = [storyboard instantiateInitialViewController];
    controller.model = [[DWUpholdConfirmTransferModel alloc] initWithCard:card transaction:transaction];

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.titleLabel.text = NSLocalizedString(@"Confirm transaction", nil);
    self.amountTitleLabel.text = NSLocalizedString(@"Amount", nil);
    self.feeTitleLabel.text = NSLocalizedString(@"Fee", nil);
    self.totalTitleLabel.text = NSLocalizedString(@"Total", nil);
    [self.confirmButton setTitle:NSLocalizedString(@"Confirm", nil) forState:UIControlStateNormal];
    [self.cancelButton setTitle:NSLocalizedString(@"Cancel", nil) forState:UIControlStateNormal];

    self.amountLabel.attributedText = [self.model amountDashString];
    self.feeLabel.attributedText = [self.model feeDashString];
    self.totalLabel.attributedText = [self.model totalDashString];

    [self mvvm_observe:@"self.model.state" with:^(typeof(self) self, NSNumber * value) {
        [self updateState];
    }];
}

#pragma mark - DWAlertKeyboardSupport

- (nullable UIView *)alertContentView {
    return self.contentView;
}

- (nullable NSLayoutConstraint *)alertContentViewCenterYConstraint {
    return self.contentViewCenterYConstraint;
}

#pragma mark - Actions

- (IBAction)confirmButtonAction:(id)sender {
    [self.model confirmWithOTPToken:nil];
}

- (IBAction)cancelButtonAction:(id)sender {
    [self.model cancel];
    [self.delegate upholdConfirmTransferViewControllerDidCancel:self];
}

#pragma mark - Private

- (void)updateState {
    switch (self.model.state) {
        case DWUpholdConfirmTransferModelStateNone: {
            self.confirmButton.hidden = NO;
            [self.activityIndicatorView stopAnimating];

            break;
        }
        case DWUpholdConfirmTransferModelStateLoading: {
            self.confirmButton.hidden = YES;
            [self.activityIndicatorView startAnimating];

            break;
        }
        case DWUpholdConfirmTransferModelStateSuccess: {
            [self.delegate upholdConfirmTransferViewControllerDidFinish:self
                                                            transaction:self.model.transaction];

            break;
        }
        case DWUpholdConfirmTransferModelStateFail: {
            self.confirmButton.hidden = NO;
            [self.activityIndicatorView stopAnimating];

            break;
        }
        case DWUpholdConfirmTransferModelStateOTP: {
            __weak typeof(self) weakSelf = self;
            [self.otpProvider requestOTPWithCompletion:^(NSString *_Nullable otpToken) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }

                if (otpToken) {
                    [strongSelf.model confirmWithOTPToken:otpToken];
                }
                else {
                    [strongSelf.model resetState];
                }
            }];

            break;
        }
    }

    if (self.model.state == DWUpholdConfirmTransferModelStateFail) {
        self.descriptionLabel.textColor = [UIColor redColor];
        self.descriptionLabel.text = NSLocalizedString(@"Something went wrong", nil);
        self.descriptionLabel.hidden = NO;
    }
    else {
        if ([self.model feeWasDeductedFromAmount]) {
            self.descriptionLabel.textColor = [UIColor darkGrayColor];
            self.descriptionLabel.text = NSLocalizedString(@"Fee will be deducted from requested amount", nil);
            self.descriptionLabel.hidden = NO;
        }
        else {
            self.descriptionLabel.hidden = YES;
        }
    }
}

@end

NS_ASSUME_NONNULL_END

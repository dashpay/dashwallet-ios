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

@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *amountTitleLabel;
@property (strong, nonatomic) IBOutlet UILabel *amountLabel;
@property (strong, nonatomic) IBOutlet UILabel *feeTitleLabel;
@property (strong, nonatomic) IBOutlet UILabel *feeLabel;
@property (strong, nonatomic) IBOutlet UILabel *totalTitleLabel;
@property (strong, nonatomic) IBOutlet UILabel *totalLabel;
@property (strong, nonatomic) IBOutlet UILabel *descriptionLabel;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *activityIndicatorView;
@property (strong, nonatomic) DWAlertAction *confirmAction;

@property (strong, nonatomic) DWUpholdConfirmTransferModel *model;

@end

@implementation DWUpholdConfirmTransferViewController

@synthesize providedActions = _providedActions;

+ (instancetype)controllerWithCard:(DWUpholdCardObject *)card transaction:(DWUpholdTransactionObject *)transaction {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"UpholdConfirmTransferStoryboard" bundle:nil];
    DWUpholdConfirmTransferViewController *controller = [storyboard instantiateInitialViewController];
    controller.model = [[DWUpholdConfirmTransferModel alloc] initWithCard:card transaction:transaction];

    return controller;
}

- (NSArray<DWAlertAction *> *)providedActions {
    if (!_providedActions) {
        __weak typeof(self) weakSelf = self;
        DWAlertAction *cancelAction = [DWAlertAction actionWithTitle:NSLocalizedString(@"cancel", nil) style:DWAlertActionStyleCancel handler:^(DWAlertAction *_Nonnull action) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf cancelButtonAction];
        }];
        DWAlertAction *confirmAction = [DWAlertAction actionWithTitle:NSLocalizedString(@"confirm", nil) style:DWAlertActionStyleDefault handler:^(DWAlertAction *_Nonnull action) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf confirmButtonAction];
        }];
        self.confirmAction = confirmAction;
        _providedActions = @[ cancelAction, confirmAction ];
    }
    return _providedActions;
}

- (DWAlertAction *)preferredAction {
    return self.confirmAction;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.titleLabel.text = NSLocalizedString(@"Confirm transaction", nil);
    self.amountTitleLabel.text = NSLocalizedString(@"Amount", nil);
    self.feeTitleLabel.text = NSLocalizedString(@"Fee", nil);
    self.totalTitleLabel.text = NSLocalizedString(@"Total", nil);

    self.amountLabel.attributedText = [self.model amountString];
    self.feeLabel.attributedText = [self.model feeString];
    self.totalLabel.attributedText = [self.model totalString];

    [self mvvm_observe:@"self.model.state" with:^(typeof(self) self, NSNumber * value) {
        [self updateState];
    }];
}

#pragma mark - Actions

- (void)confirmButtonAction {
    [self.model confirmWithOTPToken:nil];
}

- (void)cancelButtonAction {
    [self.model cancel];
    [self.delegate upholdConfirmTransferViewControllerDidCancel:self];
}

#pragma mark - Private

- (void)updateState {
    switch (self.model.state) {
        case DWUpholdConfirmTransferModelStateNone: {
            self.confirmAction.enabled = YES;
            [self.activityIndicatorView stopAnimating];

            break;
        }
        case DWUpholdConfirmTransferModelStateLoading: {
            self.confirmAction.enabled = NO;
            [self.activityIndicatorView startAnimating];

            break;
        }
        case DWUpholdConfirmTransferModelStateSuccess: {
            [self.delegate upholdConfirmTransferViewControllerDidFinish:self
                                                            transaction:self.model.transaction];

            break;
        }
        case DWUpholdConfirmTransferModelStateFail: {
            self.confirmAction.enabled = YES;
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
        self.descriptionLabel.textColor = UIColorFromRGB(0xD0021B);
        self.descriptionLabel.text = NSLocalizedString(@"Something went wrong", nil);
        self.descriptionLabel.hidden = NO;
    }
    else {
        if ([self.model feeWasDeductedFromAmount]) {
            self.descriptionLabel.textColor = UIColorFromRGB(0x787878);
            self.descriptionLabel.text = NSLocalizedString(@"Fee will be deducted from requested amount", nil);
            self.descriptionLabel.hidden = NO;
        }
        else {
            self.descriptionLabel.text = nil;
            self.descriptionLabel.hidden = YES;
        }
    }
}

@end

NS_ASSUME_NONNULL_END

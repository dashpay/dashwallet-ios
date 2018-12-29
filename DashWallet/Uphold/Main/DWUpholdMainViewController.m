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

#import "DWUpholdMainViewController.h"

#import "DWUpholdMainModel.h"
#import "DWUpholdTransferViewController.h"
#import "SFSafariViewController+DashWallet.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdMainViewController () <DWUpholdTransferViewControllerDelegate>

@property (strong, nonatomic) IBOutlet UILabel *balanceLabel;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *balanceActivityIndicator;
@property (strong, nonatomic) IBOutlet UIButton *transferButton;
@property (strong, nonatomic) IBOutlet UIButton *buyButton;

@property (strong, nonatomic) DWUpholdMainModel *model;

@end

@implementation DWUpholdMainViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"UpholdMainStoryboard" bundle:nil];
    return [storyboard instantiateInitialViewController];
}

- (DWUpholdMainModel *)model {
    if (!_model) {
        _model = [[DWUpholdMainModel alloc] init];
    }
    return _model;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"Uphold", nil);

    [self mvvm_observe:@"self.model.state" with:^(typeof(self) self, NSNumber * value) {
        switch (self.model.state) {
            case DWUpholdMainModelStateLoading: {
                [self.balanceActivityIndicator startAnimating];
                self.balanceLabel.hidden = YES;
                self.transferButton.enabled = NO;
                self.buyButton.enabled = NO;

                break;
            }
            case DWUpholdMainModelStateDone: {
                [self.balanceActivityIndicator stopAnimating];
                self.balanceLabel.hidden = NO;
                self.balanceLabel.text = [self.model.card.available descriptionWithLocale:[NSLocale currentLocale]];
                self.transferButton.enabled = YES;
                self.buyButton.enabled = YES;

                break;
            }
            case DWUpholdMainModelStateFailed: {
                [self.balanceActivityIndicator stopAnimating];
                self.balanceLabel.hidden = NO;
                self.balanceLabel.text = @"Error"; // TODO: localize
                self.transferButton.enabled = NO;
                self.buyButton.enabled = NO;

                break;
            }
        }
    }];

    [self.model fetch];
}

#pragma mark - Actions

- (IBAction)transferButtonAction:(id)sender {
    DWUpholdTransferViewController *controller = [DWUpholdTransferViewController controllerWithCard:self.model.card];
    controller.delegate = self;
    [self presentViewController:controller animated:YES completion:nil];
}

- (IBAction)buyButtonAction:(id)sender {
    NSURL *url = [self.model buyDashURL];
    if (!url) {
        return;
    }

    SFSafariViewController *controller = [SFSafariViewController dw_controllerWithURL:url];
    [self presentViewController:controller animated:YES completion:nil];
}

#pragma mark - DWUpholdTransferViewControllerDelegate

- (void)upholdTransferViewControllerDidFinish:(DWUpholdTransferViewController *)controller {
    [self.model fetch];
    [controller dismissViewControllerAnimated:YES completion:nil];
}

- (void)upholdTransferViewControllerDidCancel:(DWUpholdTransferViewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Private

- (void)requestOneTimeTokenCompletion:(void (^)(NSString *_Nullable otpToken))completion {
    UIAlertController *alertController = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"Uphold", nil)
                         message:NSLocalizedString(@"Uphold one time token is required", nil)
                  preferredStyle:UIAlertControllerStyleAlert];

    [alertController addTextFieldWithConfigurationHandler:^(UITextField *_Nonnull textField) {
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.keyboardType = UIKeyboardTypeNumberPad;
        if (@available(iOS 12.0, *)) {
            textField.textContentType = UITextContentTypeOneTimeCode;
        }
    }];

    __weak typeof(alertController) weakAlertController = alertController;

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"ok", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *_Nonnull action) {
        __strong typeof(weakAlertController) strongAlertController = weakAlertController;
        if (!strongAlertController) {
            return;
        }

        if (completion) {
            NSString *otpToken = strongAlertController.textFields.firstObject.text;
            completion(otpToken);
        }
    }];
    [alertController addAction:okAction];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"cancel", nil)
                                                           style:UIAlertActionStyleCancel
                                                         handler:^(UIAlertAction *_Nonnull action) {
                                                             if (completion) {
                                                                 completion(nil);
                                                             }
                                                         }];
    [alertController addAction:cancelAction];

    [self presentViewController:alertController animated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END

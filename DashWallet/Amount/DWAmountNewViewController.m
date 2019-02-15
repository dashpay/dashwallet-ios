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

#import "DWAmountNewViewController.h"

#import "DWAmountBaseModel.h"
#import "DWAmountKeyboard.h"
#import "DWAmountKeyboardInputViewAudioFeedback.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat HorizontalPadding() {
    CGFloat screenWidth = CGRectGetWidth([UIScreen mainScreen].bounds);
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        return (screenWidth - 400) / 2.0;
    }
    else {
        if (screenWidth > 320.0) {
            return 30.0;
        }
        else {
            return 10.0;
        }
    }
}

static CGFloat const BigAmountTextAlpha = 1.0;
static CGFloat const SmallAmountTextAlpha = 0.43;
static CGFloat const MainAmountFontSize = 26.0;
static CGFloat const SupplementaryAmountFontSize = 14.0;

@interface DWAmountNewViewController () <UITextFieldDelegate>

@property (strong, nonatomic) IBOutlet UILabel *mainAmountLabel;
@property (strong, nonatomic) IBOutlet UIImageView *convertAmountImageView;
@property (strong, nonatomic) IBOutlet UILabel *supplementaryAmountLabel;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *mainAmountLabelCenterYConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *supplementaryAmountLabelCenterYConstraint;
@property (strong, nonatomic) IBOutlet UIStackView *infoStackView;
@property (strong, nonatomic) IBOutlet UILabel *infoLabel;
@property (strong, nonatomic) IBOutlet UISwitch *infoSwitch;
@property (strong, nonatomic) IBOutlet UITextField *textField;
@property (strong, nonatomic) IBOutlet DWAmountKeyboard *amountKeyboard;
@property (strong, nonatomic) IBOutlet UILabel *addressLabel;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *containerLeadingConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *containerTrailingConstraint;
@property (null_resettable, strong, nonatomic) UIBarButtonItem *lockBarButton;
@property (null_resettable, strong, nonatomic) UIBarButtonItem *actionBarButton;
@property (null_resettable, strong, nonatomic) UIImageView *logoImageView;
@property (null_resettable, strong, nonatomic) UIButton *balanceButton;

@property (strong, nonatomic) DWAmountBaseModel *model;

@end

@implementation DWAmountNewViewController

+ (instancetype)requestController {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"AmountStoryboard" bundle:nil];
    DWAmountNewViewController *controller = [storyboard instantiateInitialViewController];
    controller.model = [[DWAmountBaseModel alloc] initWithInputIntent:DWAmountInputIntentRequest receiverAddress:nil];
    return controller;
}

- (BOOL)shouldAutorotate {
    return NO;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];

    [self mvvm_observe:@"model.locked" with:^(__typeof(self) self, NSNumber * value) {
        if (self.model.locked) {
            self.navigationItem.titleView = self.logoImageView;
            if (self.model.inputIntent == DWAmountInputIntentRequest) {
                self.navigationItem.rightBarButtonItem = self.actionBarButton;
            }
            else {
                self.navigationItem.rightBarButtonItem = self.lockBarButton;
            }
        }
        else {
            BOOL hasBalance = self.model.balanceString != nil;
            self.navigationItem.titleView = hasBalance ? self.balanceButton : self.logoImageView;
            self.navigationItem.rightBarButtonItem = self.actionBarButton;
        }
    }];

    [self mvvm_observe:@"model.balanceString" with:^(__typeof(self) self, NSAttributedString * value) {
        [self.balanceButton setAttributedTitle:value forState:UIControlStateNormal];
        [self.balanceButton sizeToFit];
    }];

    [self mvvm_observe:@"model.amount" with:^(__typeof(self) self, DWAmountObject * value) {
        self.textField.text = value.amountInternalRepresentation;
        self.mainAmountLabel.attributedText = value.dashAttributedString;
        self.supplementaryAmountLabel.attributedText = value.localCurrencyAttributedString;
        self.actionBarButton.enabled = value.plainAmount > 0;
    }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self.textField becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self.textField resignFirstResponder];
}

#pragma mark - Actions

- (void)cancelButtonAction:(id)sender {
    [self.delegate amountViewControllerDidCancel:self];
}

- (IBAction)switchAmountCurrencyAction:(id)sender {
    if (![self.model isSwapToLocalCurrencyAllowed]) {
        return;
    }

    BOOL wasSwapped = (self.model.activeType == DWAmountTypeSupplementary);
    UILabel *bigLabel = nil;
    UILabel *smallLabel = nil;
    if (wasSwapped) {
        bigLabel = self.supplementaryAmountLabel;
        smallLabel = self.mainAmountLabel;
    }
    else {
        bigLabel = self.mainAmountLabel;
        smallLabel = self.supplementaryAmountLabel;
    }
    CGFloat scale = SupplementaryAmountFontSize / MainAmountFontSize;
    bigLabel.font = [UIFont systemFontOfSize:SupplementaryAmountFontSize];
    bigLabel.transform = CGAffineTransformMakeScale(1.0 / scale, 1.0 / scale);
    smallLabel.font = [UIFont systemFontOfSize:MainAmountFontSize];
    smallLabel.transform = CGAffineTransformMakeScale(scale, scale);

    [self.model swapActiveAmountType];

    [UIView animateWithDuration:0.1 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        bigLabel.alpha = SmallAmountTextAlpha;
        smallLabel.alpha = BigAmountTextAlpha;
        bigLabel.transform = CGAffineTransformIdentity;
        smallLabel.transform = CGAffineTransformIdentity;
    }
        completion:^(BOOL finished) {
            CGFloat labelHeight = CGRectGetHeight(bigLabel.bounds);
            CGFloat maxY = MAX(CGRectGetMaxY(bigLabel.frame), CGRectGetMaxY(smallLabel.frame));
            CGFloat translation = maxY - labelHeight;
            self.mainAmountLabelCenterYConstraint.constant = wasSwapped ? 0.0 : translation;
            self.supplementaryAmountLabelCenterYConstraint.constant = wasSwapped ? 0.0 : -translation;
            [UIView animateWithDuration:0.7 delay:0.0 usingSpringWithDamping:0.5 initialSpringVelocity:1.0
                                options:UIViewAnimationOptionCurveEaseOut
                             animations:^{
                                 [self.view layoutIfNeeded];
                             }
                             completion:nil];
            [UIView animateWithDuration:0.4 animations:^{
                self.convertAmountImageView.transform = (wasSwapped ? CGAffineTransformIdentity : CGAffineTransformMakeRotation(0.9999 * M_PI));
            }];
        }];
}

- (void)lockBarButtonAction:(id)sender {
    [self.view endEditing:YES];
    [self.model unlock];
}

- (void)actionButtonAction:(id)sender {
    if ([self.model isEnteredAmountLessThenMinimumOutputAmount]) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"amount too small", nil)
                             message:[NSString stringWithFormat:NSLocalizedString(@"dash payments can't be less than %@", nil),
                                                                [self.model minimumOutputAmountFormattedString]]
                      preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"ok", nil)
                      style:UIAlertActionStyleCancel
                    handler:nil];
        [alert addAction:okAction];
        [self presentViewController:alert animated:YES completion:nil];

        [DSEventManager saveEvent:@"amount:amount_too_small"];

        return;
    }

    [self.delegate amountViewController:self didInputAmount:self.model.amount.plainAmount];
}

- (void)balanceButtonAction:(id)sender {
    [self.model selectAllFunds];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    [self.model updateAmountWithReplacementString:string range:range];

    return NO;
}

#pragma mark - Private

- (void)setupView {
    UIBarButtonItem *cancelButton =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                      target:self
                                                      action:@selector(cancelButtonAction:)];
    cancelButton.tintColor = [UIColor whiteColor];
    self.navigationItem.leftBarButtonItem = cancelButton;

    self.infoSwitch.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(3.0, 0.0), 0.7, 0.7);

    self.containerLeadingConstraint.constant = HorizontalPadding();
    self.containerTrailingConstraint.constant = -HorizontalPadding();

    CGRect inputViewRect = CGRectMake(0.0, 0.0, CGRectGetWidth([UIScreen mainScreen].bounds), 1.0);
    self.textField.inputView = [[DWAmountKeyboardInputViewAudioFeedback alloc] initWithFrame:inputViewRect];
    self.amountKeyboard.textInput = self.textField;

    self.addressLabel.text = self.model.addressTitle;

    switch (self.model.inputIntent) {
        case DWAmountInputIntentRequest: {
            self.infoStackView.hidden = YES;

            break;
        }
        case DWAmountInputIntentSend: {
            self.infoStackView.hidden = NO;

            break;
        }
    }
}

- (UIBarButtonItem *)lockBarButton {
    if (!_lockBarButton) {
        UIBarButtonItem *barButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"lock"]
                                                                      style:UIBarButtonItemStylePlain
                                                                     target:self
                                                                     action:@selector(lockBarButtonAction:)];
        barButton.tintColor = [UIColor whiteColor];
        _lockBarButton = barButton;
    }
    return _lockBarButton;
}

- (UIBarButtonItem *)actionBarButton {
    if (!_actionBarButton) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tintColor = [UIColor whiteColor];
        button.titleLabel.font = [UIFont systemFontOfSize:18.0];
        [button setTitle:self.model.actionButtonTitle forState:UIControlStateNormal];
        [button addTarget:self action:@selector(actionButtonAction:) forControlEvents:UIControlEventTouchUpInside];
        UIBarButtonItem *barButton = [[UIBarButtonItem alloc] initWithCustomView:button];
        _actionBarButton = barButton;
    }
    return _actionBarButton;
}

- (UIImageView *)logoImageView {
    if (!_logoImageView) {
        UIImageView *imageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"dashwallet-white"]];
        [imageView sizeToFit];
        _logoImageView = imageView;
    }
    return _logoImageView;
}

- (UIButton *)balanceButton {
    if (!_balanceButton) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tintColor = [UIColor whiteColor];
        [button addTarget:self action:@selector(balanceButtonAction:) forControlEvents:UIControlEventTouchUpInside];
        [button setAttributedTitle:self.model.balanceString forState:UIControlStateNormal];
        [button sizeToFit];
        _balanceButton = button;
    }
    return _balanceButton;
}

@end

NS_ASSUME_NONNULL_END

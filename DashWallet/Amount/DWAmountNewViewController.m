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
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *containerLeadingConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *containerTrailingConstraint;

@property (strong, nonatomic) DWAmountBaseModel *model;

@end

@implementation DWAmountNewViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"AmountStoryboard" bundle:nil];
    DWAmountNewViewController *controller = [storyboard instantiateInitialViewController];
    controller.model = [[DWAmountBaseModel alloc] init];
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

    [self mvvm_observe:@"model.amount" with:^(__typeof(self) self, DWAmountObject * value) {
        self.textField.text = value.amountInternalRepresentation;
        self.mainAmountLabel.attributedText = value.dashAttributedString;
        self.supplementaryAmountLabel.attributedText = value.localCurrencyAttributedString;
    }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self.textField becomeFirstResponder];
}

#pragma mark - Actions

- (void)cancelButtonAction:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
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
}

@end

NS_ASSUME_NONNULL_END

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

#import "DWOLDAmountViewController.h"

#import "DWAmountInputControl.h"
#import "DWAmountModel.h"
#import "DWNumberKeyboard.h"
#import "DWNumberKeyboardInputViewAudioFeedback.h"

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

@interface DWOLDAmountViewController () <UITextFieldDelegate>

@property (strong, nonatomic) IBOutlet DWAmountInputControl *inputControl;
@property (strong, nonatomic) IBOutlet UIStackView *infoStackView;
@property (strong, nonatomic) IBOutlet UILabel *infoLabel;
@property (strong, nonatomic) IBOutlet UISwitch *instantSendSwitch;
@property (strong, nonatomic) IBOutlet UITextField *textField;
@property (strong, nonatomic) IBOutlet DWNumberKeyboard *amountKeyboard;
@property (strong, nonatomic) IBOutlet UILabel *addressLabel;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *containerLeadingConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *containerTrailingConstraint;
@property (null_resettable, strong, nonatomic) UIBarButtonItem *actionBarButton;
@property (null_resettable, strong, nonatomic) UIImageView *logoImageView;
@property (null_resettable, strong, nonatomic) UIButton *balanceButton;

@property (strong, nonatomic) DWAmountModel *model;

@end

@implementation DWOLDAmountViewController

+ (instancetype)requestController {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"AmountStoryboard" bundle:nil];
    DWOLDAmountViewController *controller = [storyboard instantiateInitialViewController];
    controller.model = [[DWAmountModel alloc] initWithInputIntent:DWAmountInputIntent_Request
                                               sendingDestination:nil
                                                   paymentDetails:nil];
    return controller;
}

+ (instancetype)sendControllerWithDestination:(NSString *)sendingDestination
                               paymentDetails:(nullable DSPaymentProtocolDetails *)paymentDetails {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"AmountStoryboard" bundle:nil];
    DWOLDAmountViewController *controller = [storyboard instantiateInitialViewController];
    controller.model = [[DWAmountModel alloc] initWithInputIntent:DWAmountInputIntent_Send
                                               sendingDestination:sendingDestination
                                                   paymentDetails:paymentDetails];
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

    [self mvvm_observe:@"model.locked"
                  with:^(__typeof(self) self, NSNumber *value) {
                      if (self.model.locked) {
                          self.navigationItem.titleView = self.logoImageView;
                          self.navigationItem.rightBarButtonItem = self.actionBarButton;
                      }
                      else {
                          BOOL hasBalance = NO; //self.model.balanceString != nil;
                          self.navigationItem.titleView = hasBalance ? self.balanceButton : self.logoImageView;
                          self.navigationItem.rightBarButtonItem = self.actionBarButton;
                      }
                  }];

    [self mvvm_observe:@"model.balanceString"
                  with:^(__typeof(self) self, NSAttributedString *value) {
                      [self.balanceButton setAttributedTitle:value forState:UIControlStateNormal];
                      [self.balanceButton sizeToFit];
                  }];

    [self mvvm_observe:@"model.amount"
                  with:^(__typeof(self) self, DWAmountObject *value) {
                      self.textField.text = value.amountInternalRepresentation;
                      self.inputControl.source = value;
                      self.actionBarButton.enabled = value.plainAmount > 0;
                  }];

    if (self.model.inputIntent == DWAmountInputIntent_Send) {
        [self mvvm_observe:@"model.sendingOptions.state"
                      with:^(__typeof(self) self, NSNumber *value) {
                          DWAmountSendOptionsModelState state = self.model.sendingOptions.state;
                          switch (state) {
                              case DWAmountSendOptionsModelState_None: {
                                  break;
                              }
                              case DWAmountSendOptionsModelState_Regular: {
                                  self.instantSendSwitch.hidden = YES;
                                  self.infoLabel.text = NSLocalizedString(@"This transaction may take several minutes to settle.", nil);

                                  break;
                              }
                              case DWAmountSendOptionsModelState_ProposeInstantSend: {
                                  self.instantSendSwitch.hidden = NO;
                                  NSString *instantSendFee = self.model.sendingOptions.instantSendFee;
                                  NSParameterAssert(instantSendFee);
                                  self.infoLabel.text = [NSString stringWithFormat:NSLocalizedString(@"This transaction may take several minutes to settle. Complete instantly for an extra %@?", nil), instantSendFee];

                                  break;
                              }
                              case DWAmountSendOptionsModelState_AutoLocks: {
                                  self.instantSendSwitch.hidden = YES;
                                  self.infoLabel.text = NSLocalizedString(@"This transaction should settle instantly at no extra fee", nil);

                                  break;
                              }
                          }

                          [UIView animateWithDuration:0.15
                                           animations:^{
                                               CGFloat alpha = state == DWAmountSendOptionsModelState_None ? 0.0 : 1.0;
                                               self.infoStackView.alpha = alpha;
                                           }];
                      }];

        [self mvvm_observe:@"model.sendingOptions.useInstantSend"
                      with:^(__typeof(self) self, NSNumber *value) {
                          self.instantSendSwitch.on = self.model.sendingOptions.useInstantSend;
                      }];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self resetTextFieldPosition];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self.textField resignFirstResponder];
}

- (void)setInstantSendEnabled {
    //    self.model.sendingOptions.useInstantSend = YES;
}

#pragma mark - Actions

- (void)cancelButtonAction:(id)sender {
    [self.delegate amountViewControllerDidCancel:self];
}

- (IBAction)switchAmountCurrencyAction:(id)sender {
    if (![self.model isSwapToLocalCurrencyAllowed]) {
        return;
    }

    [self.model swapActiveAmountType];
    __weak typeof(self) weakSelf = self;
    [self.inputControl setActiveTypeAnimated:self.model.activeType
                                  completion:^{
                                      __strong typeof(weakSelf) strongSelf = weakSelf;
                                      if (!strongSelf) {
                                          return;
                                      }

                                      [strongSelf resetTextFieldPosition];
                                  }];
}

- (void)actionButtonAction:(id)sender {
    if ([self.model isEnteredAmountLessThenMinimumOutputAmount]) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"Amount too small", nil)
                             message:[NSString stringWithFormat:NSLocalizedString(@"Dash payments can't be less than %@", nil),
                                                                [self.model minimumOutputAmountFormattedString]]
                      preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"OK", nil)
                      style:UIAlertActionStyleCancel
                    handler:nil];
        [alert addAction:okAction];
        [self presentViewController:alert animated:YES completion:nil];

        return;
    }

    switch (self.model.inputIntent) {
        case DWAmountInputIntent_Request: {
            NSAssert([self.delegate respondsToSelector:@selector(amountViewController:didInputAmount:)],
                     @"Amount view controller's delegate should respond to amountViewController:didInputAmount:");

            [self.delegate amountViewController:self didInputAmount:self.model.amount.plainAmount];

            break;
        }
        case DWAmountInputIntent_Send: {
            NSAssert([self.delegate respondsToSelector:@selector(amountViewController:didInputAmount:wasProposedToUseInstantSend:usedInstantSend:)],
                     @"Amount view controller's delegate should respond to amountViewController:didInputAmount:wasProposedToUseInstantSend:usedInstantSend:");

            // Workaround:
            // Since our pin alert a bit hacky (it uses custom invisible UITextField added on the UIAlertController)
            // we show it after a slight delay to prevent UI bug with wrong alert position because of active first responder
            // on previous screen
            self.view.userInteractionEnabled = NO;
            self.navigationItem.rightBarButtonItem.enabled = NO;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self.delegate amountViewController:self
                                     didInputAmount:self.model.amount.plainAmount
                        wasProposedToUseInstantSend:(self.model.sendingOptions.state == DWAmountSendOptionsModelState_ProposeInstantSend)
                                    usedInstantSend:(self.model.sendingOptions.state == DWAmountSendOptionsModelState_ProposeInstantSend) && self.model.sendingOptions.useInstantSend];

                self.view.userInteractionEnabled = YES;
                self.navigationItem.rightBarButtonItem.enabled = YES;
            });

            break;
        }
    }
}

- (void)balanceButtonAction:(id)sender {
    [self.model selectAllFundsWithPreparationBlock:^{
        if (self.model.activeType == DWAmountTypeSupplementary) {
            [self switchAmountCurrencyAction:sender];
        }
    }];
}

- (IBAction)instantSendSwitchAction:(UISwitch *)sender {
    //    self.model.sendingOptions.useInstantSend = sender.isOn;
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    [self.model updateAmountWithReplacementString:string range:range];

    return NO;
}

#pragma mark - Private

- (void)resetTextFieldPosition {
    [self.textField becomeFirstResponder];
    UITextPosition *endOfDocumentPosition = self.textField.endOfDocument;
    self.textField.selectedTextRange = [self.textField textRangeFromPosition:endOfDocumentPosition
                                                                  toPosition:endOfDocumentPosition];
}

- (void)setupView {
    UIBarButtonItem *cancelButton =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                      target:self
                                                      action:@selector(cancelButtonAction:)];
    cancelButton.tintColor = [UIColor whiteColor];
    self.navigationItem.leftBarButtonItem = cancelButton;

    self.instantSendSwitch.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(3.0, 0.0), 0.7, 0.7);

    self.containerLeadingConstraint.constant = HorizontalPadding();
    self.containerTrailingConstraint.constant = -HorizontalPadding();

    CGRect inputViewRect = CGRectMake(0.0, 0.0, CGRectGetWidth([UIScreen mainScreen].bounds), 1.0);
    self.textField.inputView = [[DWNumberKeyboardInputViewAudioFeedback alloc] initWithFrame:inputViewRect];
    UITextInputAssistantItem *inputAssistantItem = self.textField.inputAssistantItem;
    inputAssistantItem.leadingBarButtonGroups = @[];
    inputAssistantItem.trailingBarButtonGroups = @[];
    self.amountKeyboard.textInput = self.textField;

    switch (self.model.inputIntent) {
        case DWAmountInputIntent_Request: {
            self.infoStackView.hidden = YES;
            self.addressLabel.text = nil;

            break;
        }
        case DWAmountInputIntent_Send: {
            self.infoStackView.hidden = NO;
            DWAmountSendingOptionsModel *sendingOptions = self.model.sendingOptions;
            NSParameterAssert(sendingOptions);
            self.addressLabel.text = [NSString stringWithFormat:NSLocalizedString(@"To: %@", nil),
                                                                sendingOptions.sendingDestination];

            break;
        }
    }
}

- (UIBarButtonItem *)actionBarButton {
    if (!_actionBarButton) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tintColor = [UIColor whiteColor];
        button.titleLabel.font = [UIFont systemFontOfSize:18.0];
        [button setTitle:self.model.actionButtonTitle forState:UIControlStateNormal];
        [button addTarget:self action:@selector(actionButtonAction:) forControlEvents:UIControlEventTouchUpInside];
        [button sizeToFit];
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
        //        [button setAttributedTitle:self.model.balanceString forState:UIControlStateNormal];
        [button sizeToFit];
        _balanceButton = button;
    }
    return _balanceButton;
}

@end

NS_ASSUME_NONNULL_END

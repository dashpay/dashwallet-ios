//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWInputUsernameViewController.h"

#import <UIViewController-KeyboardAdditions/UIViewController+KeyboardAdditions.h>

#import "DWBlueActionButton.h"
#import "DWTextField.h"
#import "DWUIKit.h"
#import "DWUsernameValidationView.h"

static CGFloat const SPACING = 16.0;
static CGFloat const CORNER_RADIUS = 10.0;
static CGFloat const TEXTFIELD_MAX_HEIGHT = 56.0;

static CGFloat BottomButtonHeight(void) {
    if (IS_IPHONE_5_OR_LESS || IS_IPHONE_6) {
        return 44.0;
    }
    else {
        return 54.0;
    }
}

NS_ASSUME_NONNULL_BEGIN

@interface DWInputUsernameViewController () <UITextFieldDelegate>

@property (null_resettable, nonatomic, copy) NSArray<DWUsernameValidationRule *> *validators;

@property (null_resettable, nonatomic, strong) UITextField *textField;
@property (null_resettable, nonatomic, strong) UIStackView *validationContentView;
@property (nonatomic, copy) NSArray<DWUsernameValidationView *> *validationViews;
@property (null_resettable, nonatomic, strong) UIButton *registerButton;

@property (nullable, nonatomic, strong) NSLayoutConstraint *contentBottomConstraint;

@end

NS_ASSUME_NONNULL_END

@implementation DWInputUsernameViewController

- (NSString *)text {
    return self.textField.text;
}

- (void)setText:(NSString *)text {
    self.textField.text = text;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    for (DWUsernameValidationRule *validationRule in self.validators) {
        DWUsernameValidationView *validationView = [[DWUsernameValidationView alloc] initWithFrame:CGRectZero];
        validationView.translatesAutoresizingMaskIntoConstraints = NO;
        validationView.title = validationRule.title;
        [validationView setValidationResult:[validationRule validateText:nil]];
        [self.validationContentView addArrangedSubview:validationView];

        [validationView.heightAnchor constraintLessThanOrEqualToConstant:26.0].active = YES;
    }

    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ self.validationContentView ]];
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    stackView.alignment = UIStackViewAlignmentTop;

    [self.view addSubview:self.textField];
    [self.view addSubview:stackView];
    [self.view addSubview:self.registerButton];

    [self updateValidationContentViewForSize:self.view.bounds.size];

    UILayoutGuide *marginsGuide = self.view.layoutMarginsGuide;
    UILayoutGuide *safeAreaGuide = self.view.safeAreaLayoutGuide;

    const CGFloat bottomPadding = [self.class deviceSpecificBottomPadding];
    // constraint relation is inverted so we can use positive padding values
    self.contentBottomConstraint = [safeAreaGuide.bottomAnchor constraintEqualToAnchor:self.registerButton.bottomAnchor
                                                                              constant:bottomPadding];

    [NSLayoutConstraint activateConstraints:@[
        [self.textField.topAnchor constraintEqualToAnchor:safeAreaGuide.topAnchor
                                                 constant:SPACING],
        [self.textField.leadingAnchor constraintEqualToAnchor:marginsGuide.leadingAnchor],
        [marginsGuide.trailingAnchor constraintEqualToAnchor:self.textField.trailingAnchor],
        [self.textField.heightAnchor constraintLessThanOrEqualToConstant:TEXTFIELD_MAX_HEIGHT],

        [stackView.topAnchor constraintEqualToAnchor:self.textField.bottomAnchor
                                            constant:SPACING],
        [stackView.leadingAnchor constraintEqualToAnchor:marginsGuide.leadingAnchor],
        [marginsGuide.trailingAnchor constraintEqualToAnchor:stackView.trailingAnchor],

        [self.registerButton.topAnchor constraintEqualToAnchor:stackView.bottomAnchor
                                                      constant:SPACING],
        [self.registerButton.leadingAnchor constraintEqualToAnchor:marginsGuide.leadingAnchor],
        [self.registerButton.trailingAnchor constraintEqualToAnchor:marginsGuide.trailingAnchor],
        [self.registerButton.heightAnchor constraintEqualToConstant:BottomButtonHeight()],
        self.contentBottomConstraint,
    ]];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    [coordinator
        animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            [self updateValidationContentViewForSize:size];
        }
                        completion:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context){

                        }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // pre-layout view to avoid undesired animation if the keyboard is shown while appearing
    [self.view layoutIfNeeded];
    [self ka_startObservingKeyboardNotifications];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self ka_stopObservingKeyboardNotifications];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.textField becomeFirstResponder];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    BOOL isDone = NO;
    if ([string isEqualToString:@"\n"]) {
        isDone = YES;
        string = @"";
    }
    NSString *text = [[self.textField.text stringByReplacingCharactersInRange:range withString:string] lowercaseString];
    BOOL canRegister = YES;
    for (NSInteger i = 0; i < self.validators.count; i++) {
        DWUsernameValidationRule *validator = self.validators[i];
        DWUsernameValidationView *validationView = self.validationContentView.arrangedSubviews[i];
        const DWUsernameValidationRuleResult result = [validator validateText:text];
        [validationView setValidationResult:result];
        canRegister &= result != DWUsernameValidationRuleResultInvalid && result != DWUsernameValidationRuleResultEmpty;
    }
    self.registerButton.enabled = canRegister;
    textField.text = text;

    if (isDone && canRegister) {
        [self registerButtonAction:self.registerButton];
    }

    return NO;
}

#pragma mark - Keyboard

- (void)ka_keyboardShowOrHideAnimationWithHeight:(CGFloat)height
                               animationDuration:(NSTimeInterval)animationDuration
                                  animationCurve:(UIViewAnimationCurve)animationCurve {
    const CGFloat bottomPadding = [self.class deviceSpecificBottomPadding];
    self.contentBottomConstraint.constant = height + bottomPadding;
    [self.view layoutIfNeeded];
}

#pragma mark - Private

- (void)updateValidationContentViewForSize:(CGSize)size {
    BOOL isLandscape = size.width > size.height;
    if (isLandscape) {
        self.validationContentView.axis = UILayoutConstraintAxisHorizontal;
    }
    else {
        self.validationContentView.axis = UILayoutConstraintAxisVertical;
    }
}

- (NSArray<DWUsernameValidationRule *> *)validators {
    if (_validators == nil) {
        _validators = @[
            [[DWUsernameValidationRule alloc]
                  initWithTitle:NSLocalizedString(@"Minimum 4 characters", @"Validation rule")
                validationBlock:^DWUsernameValidationRuleResult(NSString *_Nullable text) {
                    const NSUInteger length = text.length;
                    if (length == 0) {
                        return DWUsernameValidationRuleResultEmpty;
                    }

                    return length >= 4 ? DWUsernameValidationRuleResultValid : DWUsernameValidationRuleResultInvalid;
                }],
            [[DWUsernameValidationRule alloc]
                  initWithTitle:NSLocalizedString(@"Leters and numbers only", @"Validation rule")
                validationBlock:^DWUsernameValidationRuleResult(NSString *_Nullable text) {
                    if (text.length == 0) {
                        return DWUsernameValidationRuleResultEmpty;
                    }

                    NSCharacterSet *illegalChars = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
                    BOOL hasIllegalCharacter = [text rangeOfCharacterFromSet:illegalChars].location != NSNotFound;
                    return hasIllegalCharacter ? DWUsernameValidationRuleResultInvalid : DWUsernameValidationRuleResultValid;
                }],
            [[DWUsernameValidationRule alloc]
                  initWithTitle:NSLocalizedString(@"Maximum 24 characters", @"Validation rule")
                validationBlock:^DWUsernameValidationRuleResult(NSString *_Nullable text) {
                    return text.length < 24 ? DWUsernameValidationRuleResultHidden : DWUsernameValidationRuleResultInvalid;
                }],
        ];
    }

    return _validators;
}

- (UITextField *)textField {
    if (_textField == nil) {
        _textField = [[DWTextField alloc] initWithFrame:CGRectZero];
        _textField.translatesAutoresizingMaskIntoConstraints = NO;
        _textField.delegate = self;
        _textField.backgroundColor = [UIColor dw_backgroundColor];
        _textField.textColor = [UIColor dw_darkTitleColor];
        _textField.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
        _textField.adjustsFontForContentSizeCategory = YES;
        _textField.placeholder = NSLocalizedString(@"eg: johndoe", @"Input username textfield placeholder");
        _textField.layer.cornerRadius = CORNER_RADIUS;
        _textField.layer.masksToBounds = YES;
        _textField.autocorrectionType = UITextAutocorrectionTypeNo;
        _textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _textField.spellCheckingType = UITextSpellCheckingTypeNo;
        _textField.smartDashesType = UITextSmartDashesTypeNo;
        _textField.smartQuotesType = UITextSmartQuotesTypeNo;
        _textField.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
        _textField.returnKeyType = UIReturnKeyDone;
    }

    return _textField;
}

- (UIStackView *)validationContentView {
    if (_validationContentView == nil) {
        _validationContentView = [[UIStackView alloc] initWithFrame:CGRectZero];
        _validationContentView.translatesAutoresizingMaskIntoConstraints = NO;
        _validationContentView.axis = UILayoutConstraintAxisVertical;
        _validationContentView.spacing = 6.0;
        _validationContentView.distribution = UIStackViewDistributionFillEqually;
    }

    return _validationContentView;
}

- (UIButton *)registerButton {
    if (_registerButton == nil) {
        _registerButton = [[DWBlueActionButton alloc] initWithFrame:CGRectZero];
        _registerButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_registerButton setTitle:NSLocalizedString(@"Register", @"Button title, Register (username)")
                         forState:UIControlStateNormal];
        [_registerButton addTarget:self
                            action:@selector(registerButtonAction:)
                  forControlEvents:UIControlEventTouchUpInside];
        _registerButton.enabled = NO;
    }

    return _registerButton;
}

#pragma mark - Actions

- (void)registerButtonAction:(id)sender {
    [self.delegate inputUsernameViewControllerRegisterAction:self];
}

@end

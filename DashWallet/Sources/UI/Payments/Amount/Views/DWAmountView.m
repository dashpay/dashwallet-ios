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

#import "DWAmountView.h"

#import "DWAmountDescriptionView.h"
#import "DWAmountInputControl.h"
#import "DWAmountModel.h"
#import "DWDPAmountContactView.h"
#import "DWMaxButton.h"
#import "DWNumberKeyboard.h"
#import "DWNumberKeyboardInputViewAudioFeedback.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const KEYBOARD_HEIGHT = 215.0;
static CGFloat const SEPARATOR_HEIGHT = 1.0;
static CGFloat const DESC_KEYBOARD_PADDING = 8.0;
static CGFloat const INPUT_MAXBUTTON_PADDING = 16.0;

@interface DWAmountView () <UITextFieldDelegate, DWAmountInputControlDelegate>

@property (readonly, nonatomic, strong) DWAmountModel *model;

@property (readonly, nonatomic, strong) DWAmountInputControl *inputControl;
@property (readonly, nonatomic, strong) UIButton *maxButton;
@property (readonly, nonatomic, strong) UITextField *textField;
@property (readonly, nonatomic, strong) DWDPAmountContactView *contactView;
@property (readonly, nonatomic, strong) DWAmountDescriptionView *descriptionView;
@property (readonly, nonatomic, strong) DWNumberKeyboard *numberKeyboard;

@end

@implementation DWAmountView

- (instancetype)initWithModel:(DWAmountModel *)model demoMode:(BOOL)demoMode {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _model = model;

        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

        DWAmountInputControl *inputControl = [[DWAmountInputControl alloc] initWithFrame:CGRectZero];
        inputControl.translatesAutoresizingMaskIntoConstraints = NO;
        inputControl.backgroundColor = self.backgroundColor;
        inputControl.delegate = self;
        [inputControl setControlColor:[UIColor dw_darkTitleColor]];
        [inputControl addTarget:self
                         action:@selector(switchAmountCurrencyAction:)
               forControlEvents:UIControlEventTouchUpInside];
        _inputControl = inputControl;

        DWMaxButton *maxButton = [[DWMaxButton alloc] initWithFrame:CGRectZero];
        maxButton.translatesAutoresizingMaskIntoConstraints = NO;
        maxButton.hidden = !model.showsMaxButton;
        [maxButton addTarget:self
                      action:@selector(maxButtonAction:)
            forControlEvents:UIControlEventTouchUpInside];
        _maxButton = maxButton;

        UIStackView *inputStackView = [[UIStackView alloc]
            initWithArrangedSubviews:@[ inputControl, maxButton ]];
        inputStackView.translatesAutoresizingMaskIntoConstraints = NO;
        inputStackView.axis = UILayoutConstraintAxisVertical;
        inputStackView.alignment = UIStackViewAlignmentCenter;
        inputStackView.spacing = INPUT_MAXBUTTON_PADDING;

        UIStackView *alignmentStackView = [[UIStackView alloc]
            initWithArrangedSubviews:@[ inputStackView ]];
        alignmentStackView.translatesAutoresizingMaskIntoConstraints = NO;
        alignmentStackView.axis = UILayoutConstraintAxisHorizontal;
        alignmentStackView.alignment = UIStackViewAlignmentCenter;

        CGRect textFieldRect = CGRectMake(0.0, -500.0, 320, 44); // hides supplementary text field
        UITextField *textField = [[UITextField alloc] initWithFrame:textFieldRect];
        textField.delegate = self;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.spellCheckingType = UITextSpellCheckingTypeNo;
        CGRect inputViewRect = CGRectMake(0.0, 0.0, CGRectGetWidth([UIScreen mainScreen].bounds), 1.0);
        // In Demo Mode we don't need any input clicks. But this inputView affects appearance
        // by drawing a white line in the bottom of the screen.
        if (demoMode == NO) {
            DWNumberKeyboardInputViewAudioFeedback *inputView =
                [[DWNumberKeyboardInputViewAudioFeedback alloc] initWithFrame:inputViewRect];
            textField.inputView = inputView;
        }
        else {
            textField.inputView = [[UIView alloc] init];
        }
        UITextInputAssistantItem *inputAssistantItem = textField.inputAssistantItem;
        inputAssistantItem.leadingBarButtonGroups = @[];
        inputAssistantItem.trailingBarButtonGroups = @[];
        [self addSubview:textField];
        _textField = textField;

        DWDPAmountContactView *contactView = [[DWDPAmountContactView alloc] initWithFrame:CGRectZero];
        contactView.translatesAutoresizingMaskIntoConstraints = NO;
        contactView.hidden = YES;
        _contactView = contactView;

        DWAmountDescriptionView *descriptionView = [[DWAmountDescriptionView alloc] initWithFrame:CGRectZero];
        descriptionView.translatesAutoresizingMaskIntoConstraints = NO;
        _descriptionView = descriptionView;

        UIStackView *contentStackView = [[UIStackView alloc]
            initWithArrangedSubviews:@[ alignmentStackView, contactView, descriptionView ]];
        contentStackView.translatesAutoresizingMaskIntoConstraints = NO;
        contentStackView.axis = UILayoutConstraintAxisVertical;
        contentStackView.alignment = UIStackViewAlignmentCenter;
        contentStackView.spacing = 0.0;
        [self addSubview:contentStackView];

        UIView *separatorLineView = [[UIView alloc] init];
        separatorLineView.translatesAutoresizingMaskIntoConstraints = NO;
        separatorLineView.backgroundColor = [UIColor dw_separatorLineColor];
        [self addSubview:separatorLineView];

        DWNumberKeyboard *numberKeyboard = [[DWNumberKeyboard alloc] initWithFrame:CGRectZero];
        numberKeyboard.translatesAutoresizingMaskIntoConstraints = NO;
        numberKeyboard.textInput = textField;
        [self addSubview:numberKeyboard];
        _numberKeyboard = numberKeyboard;

        [inputControl setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                      forAxis:UILayoutConstraintAxisVertical];
        [descriptionView setContentHuggingPriority:UILayoutPriorityDefaultHigh
                                           forAxis:UILayoutConstraintAxisVertical];

        [NSLayoutConstraint activateConstraints:@[
            [descriptionView.widthAnchor constraintEqualToAnchor:contentStackView.widthAnchor],
            [contactView.widthAnchor constraintEqualToAnchor:contentStackView.widthAnchor],

            [contentStackView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [contentStackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [contentStackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [separatorLineView.topAnchor constraintEqualToAnchor:contentStackView.bottomAnchor],
            [separatorLineView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [separatorLineView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [separatorLineView.heightAnchor constraintEqualToConstant:SEPARATOR_HEIGHT],

            [numberKeyboard.topAnchor constraintEqualToAnchor:separatorLineView.bottomAnchor
                                                     constant:DESC_KEYBOARD_PADDING],
            [numberKeyboard.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [numberKeyboard.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [numberKeyboard.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [numberKeyboard.heightAnchor constraintEqualToConstant:KEYBOARD_HEIGHT],
        ]];

        // KVO

        [self mvvm_observe:DW_KEYPATH(self, model.amount)
                      with:^(__typeof(self) self, DWAmountObject *value) {
                          self.textField.text = value.amountInternalRepresentation;
                          self.inputControl.source = value;
                          [self.delegate amountView:self
                              setActionButtonEnabled:self.model.amountIsValidForProceeding];
                      }];

        [self mvvm_observe:DW_KEYPATH(self, model.descriptionModel)
                      with:^(typeof(self) self, DWAmountDescriptionViewModel *value) {
                          const BOOL isHidden = (value == nil ||
                                                 (value.text == nil && value.attributedText == nil));
                          self.descriptionView.hidden = isHidden;
                          self.descriptionView.model = self.model.descriptionModel;
                      }];

        [self mvvm_observe:DW_KEYPATH(self, model.contactItem)
                      with:^(typeof(self) self, id<DWDPBasicUserItem> value) {
                          self.contactView.hidden = value == nil;
                          self.contactView.item = value;
                      }];
    }
    return self;
}

- (void)viewWillAppear {
    [self resetTextFieldPosition];
}

- (void)viewWillDisappear {
    [self.textField resignFirstResponder];
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    [self.model reloadAttributedData];
    self.inputControl.source = self.model.amount;
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    [self.model updateAmountWithReplacementString:string range:range];

    return NO;
}

#pragma mark - DWAmountInputControlDelegate

- (void)amountInputControl:(DWAmountInputControl *)control currencySelectorAction:(UIButton *)sender {
    [self.delegate amountView:self currencySelectorAction:sender];
}

#pragma mark - Actions

- (void)switchAmountCurrencyAction:(id)sender {
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

- (void)maxButtonAction:(id)sender {
    __weak typeof(self) weakSelf = self;
    [self.model selectAllFundsWithPreparationBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (strongSelf.model.activeType == DWAmountTypeSupplementary) {
            [strongSelf switchAmountCurrencyAction:sender];
        }
    }];
}

#pragma mark - Private

- (void)resetTextFieldPosition {
    [self.textField becomeFirstResponder];
    UITextPosition *endOfDocumentPosition = self.textField.endOfDocument;
    self.textField.selectedTextRange = [self.textField textRangeFromPosition:endOfDocumentPosition
                                                                  toPosition:endOfDocumentPosition];
}

@end

NS_ASSUME_NONNULL_END

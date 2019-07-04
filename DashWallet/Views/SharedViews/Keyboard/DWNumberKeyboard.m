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

#import "DWNumberKeyboard.h"

#import "DWNumberKeyboardButton.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const VerticalSeparator = 9.0;
static CGSize const ButtonSize = {91.0, 39.0};
static const NSUInteger RowsCount = 4;
static const NSUInteger SectionsCount = 3;

@interface DWNumberKeyboard () <DWNumberKeyboardButtonDelegate> {
    BOOL _isClearButtonLongPressGestureActive;

    struct {
        unsigned int textInputSupportsShouldChangeTextInRange : 1;
        unsigned int delegateSupportsTextFieldShouldChangeCharactersInRange : 1;
        unsigned int delegateSupportsTextViewShouldChangeTextInRange : 1;
    } _delegateFlags;
}

@property (copy, nonatomic) NSArray<DWNumberKeyboardButton *> *allButtons;
@property (copy, nonatomic) NSArray<DWNumberKeyboardButton *> *digitButtons;
@property (strong, nonatomic) DWNumberKeyboardButton *separatorButton;
@property (strong, nonatomic) DWNumberKeyboardButton *clearButton;

@end

@implementation DWNumberKeyboard

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupNumberKeyboard];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setupNumberKeyboard];
    }
    return self;
}

- (void)setupNumberKeyboard {
    NSMutableArray<DWNumberKeyboardButton *> *buttons = [NSMutableArray array];
    for (DWNumberKeyboardButtonType type = DWNumberKeyboardButtonTypeDigit0; type < DWNumberKeyboardButtonTypeSeparator; type++) {
        DWNumberKeyboardButton *button = [[DWNumberKeyboardButton alloc] initWithWithType:type];
        button.delegate = self;
        [self addSubview:button];
        [buttons addObject:button];
    }
    self.digitButtons = buttons;

    DWNumberKeyboardButton *separatorButton = [[DWNumberKeyboardButton alloc] initWithWithType:DWNumberKeyboardButtonTypeSeparator];
    separatorButton.delegate = self;
    [self addSubview:separatorButton];
    self.separatorButton = separatorButton;
    [buttons addObject:separatorButton];

    DWNumberKeyboardButton *clearButton = [[DWNumberKeyboardButton alloc] initWithWithType:DWNumberKeyboardButtonTypeClear];
    clearButton.delegate = self;
    [self addSubview:clearButton];
    self.clearButton = clearButton;
    [buttons addObject:clearButton];

    self.allButtons = buttons;

    UILongPressGestureRecognizer *longPressGestureRecognizer =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                      action:@selector(clearButtonLongPressGestureRecognizerAction:)];
    longPressGestureRecognizer.cancelsTouchesInView = NO;
    [clearButton addGestureRecognizer:longPressGestureRecognizer];
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(ButtonSize.width * SectionsCount, // minimum width
                      ButtonSize.height * RowsCount + VerticalSeparator * (RowsCount - 1));
}

- (void)layoutSubviews {
    [super layoutSubviews];

    const CGFloat boundsWidth = CGRectGetWidth(self.bounds);
    const CGFloat boundsHeight = CGRectGetHeight(self.bounds);
    NSAssert(SectionsCount > 0, @"SectionsCount is invalid");
    const CGFloat horizontalSeparator = (boundsWidth - ButtonSize.width * SectionsCount) / (SectionsCount - 1);

    CGFloat left = 0.0;
    CGFloat top = 0.0;

    // Number buttons (1-9)
    for (DWNumberKeyboardButtonType i = DWNumberKeyboardButtonTypeDigit1; i < DWNumberKeyboardButtonTypeSeparator; i++) {
        DWNumberKeyboardButton *numberButton = self.digitButtons[i];
        numberButton.frame = CGRectMake(left, top, ButtonSize.width, ButtonSize.height);

        if (i % SectionsCount == 0) {
            left = 0.0;
            top += ButtonSize.height + VerticalSeparator;
        }
        else {
            left += ButtonSize.width + horizontalSeparator;
        }
    }

    // Separator
    left = 0.0;
    self.separatorButton.frame = CGRectMake(left, top, ButtonSize.width, ButtonSize.height);

    // Number button (0)
    left += ButtonSize.width + horizontalSeparator;
    DWNumberKeyboardButton *zeroButton = self.digitButtons.firstObject;
    zeroButton.frame = CGRectMake(left, top, ButtonSize.width, ButtonSize.height);

    // Clear button
    left += ButtonSize.width + horizontalSeparator;
    self.clearButton.frame = CGRectMake(left, top, ButtonSize.width, ButtonSize.height);
}

- (void)setTextInput:(nullable UIResponder<UITextInput> *)textInput {
    _delegateFlags.textInputSupportsShouldChangeTextInRange = NO;
    _delegateFlags.delegateSupportsTextFieldShouldChangeCharactersInRange = NO;
    _delegateFlags.delegateSupportsTextViewShouldChangeTextInRange = NO;

    if (![textInput conformsToProtocol:@protocol(UITextInput)]) {
        _textInput = nil;

        return;
    }

    if ([textInput respondsToSelector:@selector(shouldChangeTextInRange:replacementText:)]) {
        _delegateFlags.textInputSupportsShouldChangeTextInRange = YES;
    }
    else if ([textInput isKindOfClass:UITextField.class]) {
        id<UITextFieldDelegate> delegate = [(UITextField *)textInput delegate];
        if ([delegate respondsToSelector:@selector(textField:shouldChangeCharactersInRange:replacementString:)]) {
            _delegateFlags.delegateSupportsTextFieldShouldChangeCharactersInRange = YES;
        }
    }
    else if ([textInput isKindOfClass:UITextView.class]) {
        id<UITextViewDelegate> delegate = [(UITextView *)textInput delegate];
        if ([delegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)]) {
            _delegateFlags.delegateSupportsTextViewShouldChangeTextInRange = YES;
        }
    }

    _textInput = textInput;
}

#pragma mark - DWNumberKeyboardButtonDelegate

- (void)numberButton:(DWNumberKeyboardButton *)numberButton touchBegan:(UITouch *)touch {
    [[UIDevice currentDevice] playInputClick];

    numberButton.highlighted = YES;
}

- (void)numberButton:(DWNumberKeyboardButton *)numberButton touchMoved:(UITouch *)touch {
    for (DWNumberKeyboardButton *button in self.allButtons) {
        CGRect bounds = button.bounds;
        CGPoint point = [touch locationInView:button];
        button.highlighted = CGRectContainsPoint(bounds, point);
    }

    // reset clear button long press action if touch moved outside of its bounds
    if (_isClearButtonLongPressGestureActive) {
        CGRect bounds = self.clearButton.bounds;
        CGPoint point = [touch locationInView:self.clearButton];
        if (!CGRectContainsPoint(bounds, point)) {
            _isClearButtonLongPressGestureActive = NO;
        }
    }
}

- (void)numberButton:(DWNumberKeyboardButton *)numberButton touchEnded:(UITouch *)touch {
    for (DWNumberKeyboardButton *button in self.allButtons) {
        CGRect bounds = button.bounds;
        CGPoint point = [touch locationInView:button];
        if (CGRectContainsPoint(bounds, point)) {
            if (button != self.clearButton || !_isClearButtonLongPressGestureActive) {
                [self performButtonAction:button];
            }
        }
    }
    [self resetHighlightedButton];
}

- (void)numberButton:(DWNumberKeyboardButton *)numberButton touchCancelled:(UITouch *)touch {
    [self resetHighlightedButton];
}

#pragma mark - Private

- (void)performButtonAction:(DWNumberKeyboardButton *)sender {
    UIResponder<UITextInput> *textInput = self.textInput;
    if (!textInput) {
        return;
    }

    if (sender.type == DWNumberKeyboardButtonTypeClear) {
        [self performClearButtonAction:sender textInput:textInput];
    }
    else {
        [self performRegularButtonAction:sender textInput:textInput];
    }
}

- (void)performRegularButtonAction:(DWNumberKeyboardButton *)sender textInput:(UIResponder<UITextInput> *)textInput {
    NSString *text = nil;
    if (sender.type == DWNumberKeyboardButtonTypeSeparator) {
        text = [NSLocale currentLocale].decimalSeparator;
    }
    else {
        text = [NSString stringWithFormat:@"%ld", sender.type];
    }

    if (_delegateFlags.textInputSupportsShouldChangeTextInRange) {
        if ([textInput shouldChangeTextInRange:textInput.selectedTextRange replacementText:text]) {
            [textInput insertText:text];
        }
    }
    else if (_delegateFlags.delegateSupportsTextFieldShouldChangeCharactersInRange) {
        NSRange selectedRange = [[self class] selectedRange:textInput];
        UITextField *textField = (UITextField *)textInput;
        if ([textField.delegate textField:textField shouldChangeCharactersInRange:selectedRange replacementString:text]) {
            [textInput insertText:text];
        }
    }
    else if (_delegateFlags.delegateSupportsTextViewShouldChangeTextInRange) {
        NSRange selectedRange = [[self class] selectedRange:textInput];
        UITextView *textView = (UITextView *)textInput;
        if ([textView.delegate textView:textView shouldChangeTextInRange:selectedRange replacementText:text]) {
            [textInput insertText:text];
        }
    }
    else {
        [textInput insertText:text];
    }
}

- (void)performClearButtonAction:(DWNumberKeyboardButton *)sender textInput:(UIResponder<UITextInput> *)textInput {
    if (_delegateFlags.textInputSupportsShouldChangeTextInRange) {
        UITextRange *textRange = textInput.selectedTextRange;
        if ([textRange.start isEqual:textRange.end]) {
            UITextPosition *newStart = [textInput positionFromPosition:textRange.start inDirection:UITextLayoutDirectionLeft offset:1];
            textRange = [textInput textRangeFromPosition:newStart toPosition:textRange.end];
        }
        if ([textInput shouldChangeTextInRange:textRange replacementText:@""]) {
            [textInput deleteBackward];
        }
    }
    else if (_delegateFlags.delegateSupportsTextFieldShouldChangeCharactersInRange) {
        NSRange selectedRange = [self.class selectedRange:textInput];
        if (selectedRange.length == 0 && selectedRange.location > 0) {
            selectedRange.location--;
            selectedRange.length = 1;
        }
        UITextField *textField = (UITextField *)textInput;
        if ([textField.delegate textField:textField shouldChangeCharactersInRange:selectedRange replacementString:@""]) {
            [textInput deleteBackward];
        }
    }
    else if (_delegateFlags.delegateSupportsTextViewShouldChangeTextInRange) {
        NSRange selectedRange = [self.class selectedRange:textInput];
        if (selectedRange.length == 0 && selectedRange.location > 0) {
            selectedRange.location--;
            selectedRange.length = 1;
        }
        UITextView *textView = (UITextView *)textInput;
        if ([textView.delegate textView:textView shouldChangeTextInRange:selectedRange replacementText:@""]) {
            [textInput deleteBackward];
        }
    }
    else {
        [textInput deleteBackward];
    }
}

- (void)clearButtonLongPressGestureRecognizerAction:(UILongPressGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateBegan) {
        _isClearButtonLongPressGestureActive = YES;
        [self performClearButtonLongPressIsFirstCall:@(YES)];
    }
    else if (sender.state == UIGestureRecognizerStateEnded) {
        _isClearButtonLongPressGestureActive = NO;
    }
}

- (void)performClearButtonLongPressIsFirstCall:(NSNumber *)isFirstCall {
    UIResponder<UITextInput> *textInput = self.textInput;
    if (!textInput) {
        return;
    }

    if (_isClearButtonLongPressGestureActive) {
        if (textInput.hasText) {
            if (!isFirstCall.boolValue) {
                [[UIDevice currentDevice] playInputClick];
            }

            [self performClearButtonAction:self.clearButton textInput:textInput];
            [self performSelector:@selector(performClearButtonLongPressIsFirstCall:) withObject:@(NO) afterDelay:0.1]; // delay like in iOS keyboard
        }
        else {
            _isClearButtonLongPressGestureActive = NO;
        }
    }
}


- (void)resetHighlightedButton {
    for (DWNumberKeyboardButton *button in self.allButtons) {
        button.highlighted = NO;
    }
    _isClearButtonLongPressGestureActive = NO;
}

+ (NSRange)selectedRange:(id<UITextInput>)textInput {
    UITextRange *textRange = [textInput selectedTextRange];

    NSInteger startOffset = [textInput offsetFromPosition:textInput.beginningOfDocument toPosition:textRange.start];
    NSInteger endOffset = [textInput offsetFromPosition:textInput.beginningOfDocument toPosition:textRange.end];

    return NSMakeRange(startOffset, endOffset - startOffset);
}

@end

NS_ASSUME_NONNULL_END

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

#import "DWBlueActionButton.h"
#import "DWUIKit.h"

static CGFloat const SPACING = 16.0;
static CGFloat const CORNER_RADIUS = 10.0;
static CGFloat const TEXTFIELD_HEIGHT = 52.0;
static CGFloat const BOTTOM_BUTTON_HEIGHT = 54.0;

NS_ASSUME_NONNULL_BEGIN

@interface DWInputUsernameViewController () <UITextFieldDelegate>

@property (null_resettable, strong, nonatomic) UITextField *textField;
@property (null_resettable, strong, nonatomic) UIView *validationView;
@property (null_resettable, strong, nonatomic) UIButton *registerButton;

@property (nullable, strong, nonatomic) NSLayoutConstraint *contentBottomConstraint;

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

    [self.view addSubview:self.textField];
    [self.view addSubview:self.validationView];
    [self.view addSubview:self.registerButton];

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
        [self.textField.heightAnchor constraintEqualToConstant:TEXTFIELD_HEIGHT],

        [self.validationView.topAnchor constraintEqualToAnchor:self.textField.bottomAnchor
                                                      constant:SPACING],
        [self.validationView.leadingAnchor constraintEqualToAnchor:marginsGuide.leadingAnchor],
        [marginsGuide.trailingAnchor constraintEqualToAnchor:self.validationView.trailingAnchor],

        [self.registerButton.topAnchor constraintEqualToAnchor:self.validationView.bottomAnchor
                                                      constant:SPACING],
        [self.registerButton.leadingAnchor constraintEqualToAnchor:marginsGuide.leadingAnchor],
        [self.registerButton.trailingAnchor constraintEqualToAnchor:marginsGuide.trailingAnchor],
        [self.registerButton.heightAnchor constraintEqualToConstant:BOTTOM_BUTTON_HEIGHT],
        self.contentBottomConstraint,
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    // TODO: validation logic goes here
    self.textField.text = [self.textField.text stringByReplacingCharactersInRange:range withString:string];
    return NO;
}

#pragma mark - Private

- (UITextField *)textField {
    if (_textField == nil) {
        _textField = [[UITextField alloc] initWithFrame:CGRectZero];
        _textField.translatesAutoresizingMaskIntoConstraints = NO;
        _textField.delegate = self;
        _textField.backgroundColor = [UIColor dw_backgroundColor];
        _textField.layer.cornerRadius = CORNER_RADIUS;
        _textField.layer.masksToBounds = YES;
    }

    return _textField;
}

- (UIView *)validationView {
    if (_validationView == nil) {
        _validationView = [[UIView alloc] initWithFrame:CGRectZero];
        _validationView.translatesAutoresizingMaskIntoConstraints = NO;
        _validationView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
    }

    return _validationView;
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
    }

    return _registerButton;
}

#pragma mark - Actions

- (void)registerButtonAction:(id)sender {
    [self.delegate inputUsernameViewControllerRegisterAction:self];
}

@end

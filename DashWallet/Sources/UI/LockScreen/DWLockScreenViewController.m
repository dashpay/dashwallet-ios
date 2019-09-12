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

#import "DWLockScreenViewController.h"

#import "DWLockActionButton.h"
#import "DWLockPinInputView.h"
#import "DWNavigationController.h"
#import "DWNumberKeyboard.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat DashLogoTopPadding(void) {
    if (IS_IPHONE_5_OR_LESS) {
        return 0.0;
    }
    else if (IS_IPHONE_6) {
        return 16.0;
    }
    else {
        return 42.0;
    }
}

static CGFloat KeyboardSpacingViewHeight(void) {
    const CGFloat homeIndicatorHeight = 34.0;

    if (IS_IPAD) { // All iPads including ones with home indicator
        return homeIndicatorHeight + 24.0;
    }
    else if (DEVICE_HAS_HOME_INDICATOR) { // iPhone X-like, XS Max, X
        return homeIndicatorHeight + 4.0;
    }
    else if (IS_IPHONE_6_PLUS) { // iPhone 6 Plus-like
        return 20.0;
    }
    else { // iPhone 5-like, 6-like
        return 16.0;
    }
}

@interface DWLockScreenViewController () <DWLockPinInputViewDelegate>

@property (strong, nonatomic) IBOutlet DWLockPinInputView *pinInputView;
@property (strong, nonatomic) IBOutlet UIButton *forgotPinButton;
@property (strong, nonatomic) IBOutlet DWLockActionButton *quickReceiveButton;
@property (strong, nonatomic) IBOutlet DWLockActionButton *loginButton;
@property (strong, nonatomic) IBOutlet DWLockActionButton *scanToPayButton;
@property (strong, nonatomic) IBOutlet DWNumberKeyboard *keyboarView;
@property (strong, nonatomic) IBOutlet UIView *keyboardContainerView;

@property (strong, nonatomic) IBOutlet NSLayoutConstraint *dashLogoTopConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *keyboardSpacingViewHeightConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *keyboardBottomConstraint;

@end

@implementation DWLockScreenViewController

+ (UIViewController *)controllerEmbededInNavigationWithDelegate:(id<DWLockScreenViewControllerDelegate>)delegate {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"LockScreen" bundle:nil];
    DWLockScreenViewController *controller = [storyboard instantiateInitialViewController];
    controller.delegate = delegate;

    DWNavigationController *navigationController =
        [[DWNavigationController alloc] initWithRootViewController:controller];

    return navigationController;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - Actions

- (IBAction)forgotPinButtonAction:(UIButton *)sender {
}

- (IBAction)receiveButtonAction:(DWLockActionButton *)sender {
}

- (IBAction)loginButtonAction:(DWLockActionButton *)sender {
    [self.delegate lockScreenViewControllerDidUnlock:self];
}

- (IBAction)scanToPayButtonAction:(DWLockActionButton *)sender {
}

#pragma mark - DWNavigationFullscreenable

- (BOOL)requiresNoNavigationBar {
    return YES;
}

#pragma mark - DWLockPinInputViewDelegate

- (void)lockPinInputViewKeyboardCancelButtonAction:(DWLockPinInputView *)view {
}

- (void)lockPinInputView:(DWLockPinInputView *)view didFinishInputWithText:(NSString *)text {
}

#pragma mark - Private

- (void)setupView {
    self.pinInputView.delegate = self;
    [self.pinInputView configureWithKeyboard:self.keyboarView];

    [self.forgotPinButton setTitle:NSLocalizedString(@"Forgot PIN?", nil) forState:UIControlStateNormal];

    self.quickReceiveButton.title = NSLocalizedString(@"Quick Receive", nil);
    self.quickReceiveButton.image = [UIImage imageNamed:@"icon_lock_receive"];

    self.loginButton.title = NSLocalizedString(@"Login with PIN", nil);
    self.loginButton.image = [UIImage imageNamed:@"icon_lock_pin"];

    self.scanToPayButton.title = NSLocalizedString(@"Scan to Pay", nil);
    self.scanToPayButton.image = [UIImage imageNamed:@"icon_lock_scan_to_pay"];

    self.dashLogoTopConstraint.constant = DashLogoTopPadding();
    self.keyboardSpacingViewHeightConstraint.constant = KeyboardSpacingViewHeight();
}

@end

NS_ASSUME_NONNULL_END

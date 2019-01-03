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

#import "DWUpholdTransferViewController.h"

#import "DWAlertViewController+DWInternal.h"
#import "DWUpholdConfirmTransferViewController.h"
#import "DWUpholdOTPProvider.h"
#import "DWUpholdOTPViewController.h"
#import "DWUpholdRequestTransferViewController.h"
#import "DWUpholdSuccessTransferViewController.h"
#import "UIViewController+DWChildControllers.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdTransferViewController () <DWUpholdOTPProvider,
                                              DWUpholdRequestTransferViewControllerDelegate,
                                              DWUpholdConfirmTransferViewControllerDelegate,
                                              DWUpholdSuccessTransferViewControllerDelegate>

@property (strong, nonatomic) DWUpholdCardObject *card;
@property (strong, nonatomic) UIView *backgroundAlertView;
@property (strong, nonatomic) NSLayoutConstraint *backgroundAlertViewCenterYConstraint;
@property (strong, nonatomic) DWUpholdRequestTransferViewController *requestController;

@end

@implementation DWUpholdTransferViewController

+ (instancetype)controllerWithCard:(DWUpholdCardObject *)card {
    DWUpholdTransferViewController *controller = [[DWUpholdTransferViewController alloc] init];
    controller.card = card;
    return controller;
}

- (DWUpholdRequestTransferViewController *)requestController {
    if (!_requestController) {
        _requestController = [DWUpholdRequestTransferViewController controllerWithCard:self.card];
        _requestController.delegate = self;
        _requestController.otpProvider = self;
    }
    return _requestController;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    UIView *backgroundAlertView = [[UIView alloc] initWithFrame:CGRectZero];
    backgroundAlertView.translatesAutoresizingMaskIntoConstraints = NO;
    backgroundAlertView.backgroundColor = [UIColor whiteColor];
    backgroundAlertView.layer.cornerRadius = 8.0;
    backgroundAlertView.layer.masksToBounds = YES;
    [self.view addSubview:backgroundAlertView];
    [NSLayoutConstraint activateConstraints:@[
        [backgroundAlertView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [backgroundAlertView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        (self.backgroundAlertViewCenterYConstraint = [backgroundAlertView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]),
        [backgroundAlertView.widthAnchor constraintEqualToAnchor:backgroundAlertView.heightAnchor],
    ]];
    self.backgroundAlertView = backgroundAlertView;

    [self dw_displayViewController:self.requestController];
}

#pragma mark - DWAlertKeyboardSupport

- (nullable UIView *)alertContentView {
    return self.backgroundAlertView;
}

- (nullable NSLayoutConstraint *)alertContentViewCenterYConstraint {
    return self.backgroundAlertViewCenterYConstraint;
}

#pragma mark - DWUpholdOTPProvider

- (void)requestOTPWithCompletion:(void (^)(NSString *_Nullable otpToken))completion {
    DWUpholdOTPViewController *otpController = [DWUpholdOTPViewController controllerWithCompletion:^(DWUpholdOTPViewController *_Nonnull controller, NSString *_Nullable otpToken) {
        [controller dismissViewControllerAnimated:YES completion:nil];

        if (completion) {
            completion(otpToken);
        }
    }];
    [self presentViewController:otpController animated:YES completion:nil];
}

#pragma mark - DWUpholdRequestTransferViewControllerDelegate

- (void)upholdRequestTransferViewController:(DWUpholdRequestTransferViewController *)controller
                      didProduceTransaction:(DWUpholdTransactionObject *)transaction {
    DWUpholdConfirmTransferViewController *confirmController =
        [DWUpholdConfirmTransferViewController controllerWithCard:self.card transaction:transaction];
    confirmController.delegate = self;
    confirmController.otpProvider = self;
    [self dw_performTransitionToViewController:confirmController completion:nil];
}

- (void)upholdRequestTransferViewControllerDidCancel:(DWUpholdRequestTransferViewController *)controller {
    [self.delegate upholdTransferViewControllerDidCancel:self];
}

#pragma mark - DWUpholdConfirmTransferViewControllerDelegate

- (void)upholdConfirmTransferViewControllerDidCancel:(DWUpholdConfirmTransferViewController *)controller {
    [self dw_performTransitionToViewController:self.requestController completion:nil];
}

- (void)upholdConfirmTransferViewControllerDidFinish:(DWUpholdConfirmTransferViewController *)controller transaction:(DWUpholdTransactionObject *)transaction {
    DWUpholdSuccessTransferViewController *successController =
        [DWUpholdSuccessTransferViewController controllerWithTransaction:transaction];
    successController.delegate = self;
    [self dw_performTransitionToViewController:successController completion:nil];
}

#pragma mark - DWUpholdSuccessTransferViewControllerDelegate

- (void)upholdSuccessTransferViewControllerDidFinish:(DWUpholdSuccessTransferViewController *)controller {
    [self.delegate upholdTransferViewControllerDidFinish:self];
}

- (void)upholdSuccessTransferViewControllerDidFinish:(DWUpholdSuccessTransferViewController *)controller
                                  openTransactionURL:(NSURL *)url {
    [self.delegate upholdTransferViewControllerDidFinish:self openTransactionURL:url];
}

#pragma mark - Internal

- (void)keyboardWillShowOrHideWithHeight:(CGFloat)height {
    [super keyboardWillShowOrHideWithHeight:height];

    UIViewController<DWAlertViewControllerKeyboardSupport> *controller = (UIViewController<DWAlertViewControllerKeyboardSupport> *)self.dw_currentChildController;
    UIView *alertContentView = nil;
    NSLayoutConstraint *alertContentViewCenterYConstraint = nil;
    if ([controller respondsToSelector:@selector(alertContentView)]) {
        alertContentView = controller.alertContentView;
    }
    if ([controller respondsToSelector:@selector(alertContentViewCenterYConstraint)]) {
        alertContentViewCenterYConstraint = controller.alertContentViewCenterYConstraint;
    }

    if (alertContentView && alertContentViewCenterYConstraint) {
        [self.class updateContraintForKeyboardHeight:height
                                          parentView:controller.view
                                    alertContentView:alertContentView
                   alertContentViewCenterYConstraint:alertContentViewCenterYConstraint];
    }
}

- (void)keyboardShowOrHideAnimation {
    [super keyboardShowOrHideAnimation];

    UIViewController<DWAlertViewControllerKeyboardSupport> *controller = (UIViewController<DWAlertViewControllerKeyboardSupport> *)self.dw_currentChildController;
    UIView *alertContentView = nil;
    NSLayoutConstraint *alertContentViewCenterYConstraint = nil;
    if ([controller respondsToSelector:@selector(alertContentView)]) {
        alertContentView = controller.alertContentView;
    }
    if ([controller respondsToSelector:@selector(alertContentViewCenterYConstraint)]) {
        alertContentViewCenterYConstraint = controller.alertContentViewCenterYConstraint;
    }

    if (alertContentView && alertContentViewCenterYConstraint) {
        [controller.view layoutIfNeeded];
    }
}

@end

NS_ASSUME_NONNULL_END

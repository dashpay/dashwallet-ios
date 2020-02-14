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

#import "DWCreateUsernameViewController.h"

#import "DWConfirmUsernameViewController.h"
#import "DWContainerViewController.h"
#import "DWInputUsernameViewController.h"
#import "DWUIKit.h"
#import "DWUsernameHeaderView.h"
#import "DWUsernamePendingViewController.h"
#import "UIViewController+DWEmbedding.h"

static CGFloat const HeaderHeight(void) {
    if (IS_IPHONE_6 || IS_IPHONE_5_OR_LESS) {
        return 125.0;
    }
    else {
        return 231.0;
    }
}

NS_ASSUME_NONNULL_BEGIN

@interface DWCreateUsernameViewController () <DWInputUsernameViewControllerDelegate, DWConfirmUsernameViewControllerDelegate>

@property (null_resettable, nonatomic, strong) DWContainerViewController *containerController;

@property (null_resettable, nonatomic, strong) DWUsernameHeaderView *headerView;
@property (null_resettable, nonatomic, strong) UIView *contentView;

@property (null_resettable, nonatomic, strong) DWInputUsernameViewController *inputUsername;

@end

NS_ASSUME_NONNULL_END

@implementation DWCreateUsernameViewController

- (NSString *)actionButtonTitle {
    return NSLocalizedString(@"Register", @"Action button title: Register (username)");
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.clipsToBounds = YES;
    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    [self.view addSubview:self.contentView];
    [self.view addSubview:self.headerView];

    [NSLayoutConstraint activateConstraints:@[
        [self.headerView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.headerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.view.trailingAnchor constraintEqualToAnchor:self.headerView.trailingAnchor],
        [self.headerView.heightAnchor constraintEqualToConstant:HeaderHeight()],

        [self.contentView.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.view.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.view.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
    ]];

    [self dw_embedChild:self.containerController inContainer:self.contentView];

    [self.containerController displayViewController:self.inputUsername];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.headerView showInitialAnimation];
}

- (DWContainerViewController *)containerController {
    if (_containerController == nil) {
        _containerController = [[DWContainerViewController alloc] init];
    }

    return _containerController;
}

- (UIView *)contentView {
    if (_contentView == nil) {
        _contentView = [[UIView alloc] initWithFrame:CGRectZero];
        _contentView.translatesAutoresizingMaskIntoConstraints = NO;
    }

    return _contentView;
}

- (DWUsernameHeaderView *)headerView {
    if (_headerView == nil) {
        _headerView = [[DWUsernameHeaderView alloc] initWithFrame:CGRectZero];
        _headerView.translatesAutoresizingMaskIntoConstraints = NO;
        _headerView.preservesSuperviewLayoutMargins = YES;
        _headerView.titleBuilder = ^NSAttributedString *_Nonnull {
            // TODO: DynamicType
            NSDictionary *regularAttributes = @{
                NSFontAttributeName : [UIFont dw_regularFontOfSize:22.0],
                NSForegroundColorAttributeName : [UIColor dw_darkTitleColor],
            };

            NSDictionary *emphasizedAttributes = @{
                NSFontAttributeName : [UIFont dw_mediumFontOfSize:22.0],
                NSForegroundColorAttributeName : [UIColor dw_darkTitleColor],
            };

            NSAttributedString *chooseYourString =
                [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Choose your", @"Choose your Dash username")
                                                attributes:regularAttributes];

            NSAttributedString *spaceString =
                [[NSAttributedString alloc] initWithString:@"\n"
                                                attributes:regularAttributes];

            NSAttributedString *dashUsernameString =
                [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Dash username", nil)
                                                attributes:emphasizedAttributes];

            NSMutableAttributedString *resultString = [[NSMutableAttributedString alloc] init];
            [resultString beginEditing];
            [resultString appendAttributedString:chooseYourString];
            [resultString appendAttributedString:spaceString];
            [resultString appendAttributedString:dashUsernameString];
            [resultString endEditing];

            return resultString;
        };
        [_headerView.cancelButton addTarget:self
                                     action:@selector(cancelButtonAction)
                           forControlEvents:UIControlEventTouchUpInside];
    }

    return _headerView;
}

- (DWInputUsernameViewController *)inputUsername {
    if (_inputUsername == nil) {
        _inputUsername = [[DWInputUsernameViewController alloc] init];
        _inputUsername.delegate = self;
    }

    return _inputUsername;
}

#pragma mark - DWInputUsernameViewControllerDelegate

- (void)inputUsernameViewControllerRegisterAction:(DWInputUsernameViewController *)inputController {
    DWConfirmUsernameViewController *confirmController = [[DWConfirmUsernameViewController alloc] init];
    confirmController.delegate = self;
    [self presentViewController:confirmController animated:YES completion:nil];
}

#pragma mark - DWConfirmUsernameViewControllerDelegate

- (void)confirmUsernameViewControllerDidConfirm:(DWConfirmUsernameViewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:nil];

    DWUsernamePendingViewController *pendingController = [[DWUsernamePendingViewController alloc] init];
    pendingController.username = self.inputUsername.text;
    [self.navigationController setViewControllers:@[ pendingController ] animated:YES];
}

#pragma mark - Actions

- (void)cancelButtonAction {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

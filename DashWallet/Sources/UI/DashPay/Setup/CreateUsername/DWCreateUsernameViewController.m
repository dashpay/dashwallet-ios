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

#import "DWInputUsernameViewController.h"
#import "DWUIKit.h"
#import "UIViewController+DWEmbedding.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWCreateUsernameViewController () <DWInputUsernameViewControllerDelegate>

@property (readonly, nonatomic, strong) id<DWDashPayProtocol> dashPayModel;

@property (null_resettable, nonatomic, strong) UIScrollView *scrollView;
@property (null_resettable, nonatomic, strong) DWInputUsernameViewController *inputUsername;

@end

NS_ASSUME_NONNULL_END

@implementation DWCreateUsernameViewController

- (instancetype)initWithDashPayModel:(id<DWDashPayProtocol>)dashPayModel {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _dashPayModel = dashPayModel;
    }
    return self;
}

- (NSAttributedString *)attributedTitle {
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
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.clipsToBounds = YES;
    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    [self.view addSubview:self.scrollView];

    const BOOL isLandscape = CGRectGetWidth(self.view.bounds) > CGRectGetHeight(self.view.bounds);

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.view.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [self.view.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [self.scrollView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor],
    ]];

    [self dw_embedChild:self.inputUsername inContainer:self.scrollView];

    NSLayoutConstraint *heightConstraint = [self.inputUsername.view.heightAnchor constraintEqualToAnchor:self.scrollView.heightAnchor];
    heightConstraint.priority = UILayoutPriorityRequired - 1;

    [NSLayoutConstraint activateConstraints:@[
        heightConstraint,
        [self.inputUsername.view.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor]
    ]];
}

- (UIScrollView *)scrollView {
    if (_scrollView == nil) {
        _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
        _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    }

    return _scrollView;
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
    [self.delegate createUsernameViewController:self registerUsername:inputController.text];
}

#pragma mark - Actions

- (void)cancelButtonAction {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

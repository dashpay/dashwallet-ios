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

#import "DWVerifiedSuccessfullyViewController.h"

#import "UIFont+DWFont.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWVerifiedSuccessfullyViewController ()

@property (strong, nonatomic) IBOutlet UIScrollView *scrollView;
@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *descriptionLabel;
@property (strong, nonatomic) IBOutlet UIButton *continueButton;

@end

@implementation DWVerifiedSuccessfullyViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"VerifiedSuccessfully" bundle:nil];
    return [storyboard instantiateInitialViewController];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.scrollView flashScrollIndicators];
}

#pragma mark - DWNavigationFullscreenable

- (BOOL)requiresNoNavigationBar {
    return YES;
}

#pragma mark - Actions

- (IBAction)continueButtonAction:(id)sender {
    [self.delegate secureWalletRoutineDidVerify:self];
}

#pragma mark - Private

- (void)setupView {
    self.titleLabel.text = NSLocalizedString(@"Verified Successfully", nil);
    self.descriptionLabel.text = NSLocalizedString(@"Your wallet is secured now. You can use your recovery phrase anytime to recover your account on another device.", nil);
    [self.continueButton setTitle:NSLocalizedString(@"Continue", nil) forState:UIControlStateNormal];

    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle2];
    self.descriptionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
}

@end

NS_ASSUME_NONNULL_END

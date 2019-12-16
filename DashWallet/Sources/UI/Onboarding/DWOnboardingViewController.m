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

#import "DWOnboardingViewController.h"

#import "DWAppRootViewController.h"
#import "DWRootModelStub.h"
#import "UIViewController+DWEmbedding.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWOnboardingViewController ()

@property (strong, nonatomic) IBOutlet UIView *miniWalletView;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *contentBottomConstraint;
@property (strong, nonatomic) IBOutlet UIButton *skipButton;

@property (nonatomic, strong) DWAppRootViewController *rootController;

@end

@implementation DWOnboardingViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Onboarding" bundle:nil];
    DWOnboardingViewController *controller = [storyboard instantiateInitialViewController];

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    // There is an issue with layout margins of "minified" root controller
    // When the scale transformation is applied to the hosted view safe area is ignored and layout margins of
    // children views within root controller becomes invalid.
    // Restore safe area insets and hack horizontal insets a bit so it's fine for both root and their children.
    UIEdgeInsets insets = self.view.safeAreaInsets;
    insets.left = 10.0;
    insets.right = 10.0;
    self.rootController.additionalSafeAreaInsets = insets;
}

#pragma mark - Actions

- (IBAction)skipButtonAction:(id)sender {
    [self.delegate onboardingViewControllerDidFinish:self];
}

#pragma mark - Private

- (void)setupView {
    self.miniWalletView.transform = CGAffineTransformMakeScale(0.65, 0.65);

    DWRootModelStub *model = [[DWRootModelStub alloc] init];
    DWAppRootViewController *controller = [[DWAppRootViewController alloc] initWithModel:model];
    [self dw_embedChild:controller inContainer:self.miniWalletView];
    self.rootController = controller;
}

@end

NS_ASSUME_NONNULL_END

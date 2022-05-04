//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import "DWExploreTestnetViewController.h"

#import "DWColoredButton.h"
#import "DWEnvironment.h"
#import "DWExploreHeaderView.h"
#import "DWExploreTestnetContentsView.h"
#import "DWScrollingViewController.h"
#import "DWUIKit.h"
#import "UINavigationBar+DWAppearance.h"
#import "dashwallet-Swift.h"

@implementation DWExploreTestnetViewController

- (BOOL)requiresNoNavigationBar {
    return YES;
}

- (void)showWhereToSpendViewController {
    
    DWExploreTestnetViewController* __weak weakSelf = self;
    
    ExploreWhereToSpendViewController *vc = [[ExploreWhereToSpendViewController alloc] init];
    vc.payWithDashHandler = ^{
        [weakSelf openPaymentsScreen];
    };
    
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openPaymentsScreen {
    [self.delegate exploreTestnetViewControllerShowSendPayment:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_darkBlueColor];
    
    // Setup navigation bar
    [self.navigationController.navigationBar dw_configureForWhiteAppearance];
    self.navigationController.navigationBar.shadowImage = nil;
    self.navigationController.navigationBar.translucent = YES;
    [self.navigationController.navigationBar dw_applyStandardAppearance];
    
    UINavigationBarAppearance *standardAppearance = self.navigationController.navigationBar.standardAppearance;
    standardAppearance.shadowColor = [UIColor separatorColor];
    
    self.navigationController.navigationBar.scrollEdgeAppearance = standardAppearance;
    self.navigationController.navigationBar.compactAppearance = standardAppearance;
    
    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:contentView];

    // Contents
    DWExploreHeaderView *headerView = [[DWExploreHeaderView alloc] init];
    headerView.translatesAutoresizingMaskIntoConstraints = NO;
    headerView.image = [UIImage imageNamed:@"image.explore.dash.wallet"];
    headerView.title = NSLocalizedString(@"Explore Dash", nil);
    headerView.subtitle = NSLocalizedString(@"Easily shop with your DASH at over 155,000 locations and online merchants", nil);

    DWExploreTestnetViewController* __weak weakSelf = self;
    
    DWExploreTestnetContentsView *contentsView = [[DWExploreTestnetContentsView alloc] init];
    contentsView.whereToSpendHandler =  ^{
        [weakSelf showWhereToSpendViewController];
    };
    contentsView.atmHandler = ^{
        
    };
    
    contentsView.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *parentView = [[UIStackView alloc] init];
    parentView.translatesAutoresizingMaskIntoConstraints = NO;
    parentView.distribution = UIStackViewDistributionEqualSpacing;
    parentView.axis = UILayoutConstraintAxisVertical;
    parentView.spacing = 34;

    [parentView addArrangedSubview:headerView];
    [parentView addArrangedSubview:contentsView];
    [self.view addSubview:parentView];
    
    [NSLayoutConstraint activateConstraints:@[
        [headerView.widthAnchor constraintLessThanOrEqualToConstant:kExploreHeaderViewHeight],
        
        [parentView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [parentView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [parentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [parentView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)buttonAction {
    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
    NSString *paymentAddress = account.receiveAddress;
    if (paymentAddress == nil) {
        return;
    }

    [UIPasteboard generalPasteboard].string = paymentAddress;
    NSURL *url = [NSURL URLWithString:@"https://testnet-faucet.dash.org/"];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

@end

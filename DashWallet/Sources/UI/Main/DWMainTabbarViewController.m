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

#import "DWMainTabbarViewController.h"

#import "DWHomeViewController.h"
#import "DWMainMenuViewController.h"
#import "DWNavigationController.h"
#import "DWPaymentsViewController.h"
#import "DWTabBarView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const ANIMATION_DURATION = 0.35;

@interface DWMainTabbarViewController () <DWTabBarViewDelegate,
                                          DWPaymentsViewControllerDelegate,
                                          DWHomeViewControllerDelegate,
                                          UINavigationControllerDelegate,
                                          DWWipeDelegate,
                                          DWMainMenuViewControllerDelegate>

@property (nonatomic, strong) id<DWHomeProtocol> homeModel;

@property (nullable, nonatomic, strong) UIView *contentView;
@property (nullable, nonatomic, strong) DWTabBarView *tabBarView;
@property (nullable, nonatomic, strong) NSLayoutConstraint *tabBarBottomConstraint;
@property (nullable, nonatomic, strong) NSLayoutConstraint *contentBottomConstraint;

@property (null_resettable, nonatomic, strong) DWNavigationController *homeNavigationController;
@property (null_resettable, nonatomic, strong) DWNavigationController *menuNavigationController;
@property (nonatomic, weak) DWHomeViewController *homeController;

@end

@implementation DWMainTabbarViewController

+ (instancetype)controllerWithHomeModel:(id<DWHomeProtocol>)homeModel {
    DWMainTabbarViewController *controller = [[DWMainTabbarViewController alloc] init];
    controller.homeModel = homeModel;

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
    [self setupControllers];
}

- (UIView *)containerView {
    return self.contentView;
}

#pragma mark - Public

- (void)performScanQRCodeAction {
    [self transitionToViewController:self.homeNavigationController
                            withType:DWContainerTransitionType_WithoutAnimation];
    [self.tabBarView updateSelectedTabButton:DWTabBarViewButtonType_Home];
    [self.homeController performScanQRCodeAction];
}

- (void)performPayToURL:(NSURL *)url {
    [self transitionToViewController:self.homeNavigationController
                            withType:DWContainerTransitionType_WithoutAnimation];
    [self.tabBarView updateSelectedTabButton:DWTabBarViewButtonType_Home];
    [self.homeController performPayToURL:url];
}

- (void)handleFile:(NSData *)file {
    [self transitionToViewController:self.homeNavigationController
                            withType:DWContainerTransitionType_WithoutAnimation];
    [self.tabBarView updateSelectedTabButton:DWTabBarViewButtonType_Home];
    [self.homeController handleFile:file];
}

#pragma mark - DWTabBarViewDelegate

- (void)tabBarView:(DWTabBarView *)tabBarView didTapButtonType:(DWTabBarViewButtonType)buttonType {
    switch (buttonType) {
        case DWTabBarViewButtonType_Home: {
            if (self.currentController == self.homeNavigationController) {
                return;
            }

            [self transitionToViewController:self.homeNavigationController
                                    withType:DWContainerTransitionType_WithoutAnimation];

            break;
        }
        case DWTabBarViewButtonType_Others: {
            if (self.currentController == self.menuNavigationController) {
                return;
            }

            [self transitionToViewController:self.menuNavigationController
                                    withType:DWContainerTransitionType_WithoutAnimation];

            break;
        }
    }
    [tabBarView updateSelectedTabButton:buttonType];
}

- (void)tabBarViewDidOpenPayments:(DWTabBarView *)tabBarView {
    [self showPaymentsControllerWithActivePage:DWPaymentsViewControllerIndex_None];
}

- (void)tabBarViewDidClosePayments:(DWTabBarView *)tabBarView {
    if (!self.modalController) {
        return;
    }

    tabBarView.userInteractionEnabled = NO;
    [tabBarView setPaymentsButtonOpened:NO];

    [self hideModalControllerCompletion:^{
        tabBarView.userInteractionEnabled = YES;
    }];
}

#pragma mark - DWPaymentsViewControllerDelegate

- (void)paymentsViewControllerDidCancel:(DWPaymentsViewController *)controller {
    [self tabBarViewDidClosePayments:self.tabBarView];
}

#pragma mark - DWHomeViewControllerDelegate

- (void)homeViewController:(DWHomeViewController *)controller payButtonAction:(UIButton *)sender {
    [self showPaymentsControllerWithActivePage:DWPaymentsViewControllerIndex_Pay];
}

- (void)homeViewController:(DWHomeViewController *)controller receiveButtonAction:(UIButton *)sender {
    [self showPaymentsControllerWithActivePage:DWPaymentsViewControllerIndex_Receive];
}

#pragma mark - DWWipeDelegate

- (void)didWipeWallet {
    [self.delegate didWipeWallet];
}

#pragma mark - DWMainMenuViewControllerDelegate

- (void)mainMenuViewControllerImportPrivateKey:(DWMainMenuViewController *)controller {
    [self performScanQRCodeAction];
}

#pragma mark - UINavigationControllerDelegate

- (void)navigationController:(UINavigationController *)navigationController
      willShowViewController:(UIViewController *)viewController
                    animated:(BOOL)animated {
    [self setTabBarHiddenAnimated:viewController.hidesBottomBarWhenPushed animated:YES];
}

- (void)navigationController:(UINavigationController *)navigationController
       didShowViewController:(UIViewController *)viewController
                    animated:(BOOL)animated {
    [self setTabBarHiddenAnimated:viewController.hidesBottomBarWhenPushed animated:NO];
}

#pragma mark - Private

- (DWNavigationController *)homeNavigationController {
    if (!_homeNavigationController) {
        DWHomeViewController *homeController = [[DWHomeViewController alloc] init];
        homeController.model = self.homeModel;
        homeController.delegate = self;
        self.homeController = homeController;

        _homeNavigationController = [[DWNavigationController alloc] initWithRootViewController:homeController];
        _homeNavigationController.delegate = self;
    }

    return _homeNavigationController;
}

- (DWNavigationController *)menuNavigationController {
    if (!_menuNavigationController) {
        DWMainMenuViewController *menuController =
            [[DWMainMenuViewController alloc] initWithBalanceDisplayOptions:self.homeModel.balanceDisplayOptions];
        menuController.delegate = self;

        _menuNavigationController = [[DWNavigationController alloc] initWithRootViewController:menuController];
        _menuNavigationController.delegate = self;
    }

    return _menuNavigationController;
}

- (void)setupView {
    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    UIView *contentView = [[UIView alloc] initWithFrame:CGRectZero];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.backgroundColor = self.view.backgroundColor;
    [self.view addSubview:contentView];
    self.contentView = contentView;

    DWTabBarView *tabBarView = [[DWTabBarView alloc] initWithFrame:CGRectZero];
    tabBarView.translatesAutoresizingMaskIntoConstraints = NO;
    tabBarView.delegate = self;
    [self.view addSubview:tabBarView];
    self.tabBarView = tabBarView;

    self.contentBottomConstraint = [contentView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
    self.tabBarBottomConstraint = [tabBarView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];

    [NSLayoutConstraint activateConstraints:@[
        [contentView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [tabBarView.topAnchor constraintEqualToAnchor:contentView.bottomAnchor],
        [tabBarView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tabBarView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.tabBarBottomConstraint,
    ]];
}

- (void)showPaymentsControllerWithActivePage:(DWPaymentsViewControllerIndex)pageIndex {
    if (self.modalController) {
        return;
    }

    self.tabBarView.userInteractionEnabled = NO;
    [self.tabBarView setPaymentsButtonOpened:YES];

    id<DWHomeProtocol> homeModel = self.homeModel;
    NSParameterAssert(homeModel);
    DWReceiveModel *receiveModel = homeModel.receiveModel;
    DWPayModel *payModel = homeModel.payModel;
    id<DWTransactionListDataProviderProtocol> dataProvider = [homeModel getDataProvider];
    DWPaymentsViewController *controller = [DWPaymentsViewController controllerWithReceiveModel:receiveModel
                                                                                       payModel:payModel
                                                                                   dataProvider:dataProvider];
    controller.delegate = self;
    controller.currentIndex = pageIndex;
    DWNavigationController *navigationController =
        [[DWNavigationController alloc] initWithRootViewController:controller];
    navigationController.delegate = self;

    [self displayModalViewController:navigationController
                          completion:^{
                              self.tabBarView.userInteractionEnabled = YES;
                          }];
}

- (void)setupControllers {
    DWNavigationController *navigationController = self.homeNavigationController;
    [self displayViewController:navigationController];
}

- (void)setTabBarHiddenAnimated:(BOOL)hidden animated:(BOOL)animated {
    if (hidden) {
        self.tabBarBottomConstraint.active = NO;
        self.contentBottomConstraint.active = YES;
    }
    else {
        self.contentBottomConstraint.active = NO;
        self.tabBarBottomConstraint.active = YES;
    }

    const CGFloat alpha = hidden ? 0.0 : 1.0;

    if (self.tabBarView.alpha == alpha) {
        return;
    }

    if (@available(iOS 13.0, *)) {
        // NOP
    }
    else {
        [self.view layoutSubviews];
    }

    [UIView animateWithDuration:animated ? ANIMATION_DURATION : 0.0
                     animations:^{
                         if (@available(iOS 13.0, *)) {
                             [self.view layoutSubviews];
                         }

                         self.tabBarView.alpha = alpha;
                     }];
}

@end

NS_ASSUME_NONNULL_END

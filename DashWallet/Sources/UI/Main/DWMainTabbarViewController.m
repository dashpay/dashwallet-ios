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
#import "DWTabBarView.h"
#import "UIColor+DWStyle.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWMainTabbarViewController ()

@property (nullable, nonatomic, copy) NSArray<UIViewController *> *viewControllers;
@property (nullable, nonatomic, strong) UIViewController *currentController;

@property (nullable, nonatomic, strong) UIView *contentView;
@property (nullable, nonatomic, strong) DWTabBarView *tabBarView;

@end

@implementation DWMainTabbarViewController

+ (instancetype)controller {
    DWMainTabbarViewController *controller = [[DWMainTabbarViewController alloc] init];

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
    [self setupControllers];
}

- (nullable UIViewController *)childViewControllerForStatusBarStyle {
    return self.currentController;
}

- (nullable UIViewController *)childViewControllerForStatusBarHidden {
    return self.currentController;
}

#pragma mark - Private

- (void)setupView {
    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    UIView *contentView = [[UIView alloc] initWithFrame:CGRectZero];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.backgroundColor = self.view.backgroundColor;
    [self.view addSubview:contentView];
    self.contentView = contentView;

    DWTabBarView *tabBarView = [[DWTabBarView alloc] initWithFrame:CGRectZero];
    tabBarView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:tabBarView];
    self.tabBarView = tabBarView;

    [NSLayoutConstraint activateConstraints:@[
        [contentView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [tabBarView.topAnchor constraintEqualToAnchor:contentView.bottomAnchor],
        [tabBarView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tabBarView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tabBarView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)setupControllers {
    UIViewController *homeController = [DWHomeViewController controllerEmbededInNavigation];

    self.viewControllers = @[ homeController ];

    [self displayViewController:homeController];
}

- (void)displayViewController:(UIViewController *)controller {
    NSParameterAssert(controller);

    UIView *contentView = self.contentView;
    UIView *childView = controller.view;

    [self addChildViewController:controller];

    childView.frame = contentView.bounds;
    childView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [contentView addSubview:childView];

    [controller didMoveToParentViewController:self];

    self.currentController = controller;

    [self setNeedsStatusBarAppearanceUpdate];
}

@end

NS_ASSUME_NONNULL_END

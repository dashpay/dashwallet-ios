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

#import "DWRootNavigationController.h"

#import "DWRootModel.h"
#import "DWSetupViewController.h"
#import "UIColor+DWStyle.h"
#import "UIFont+DWFont.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWRootNavigationController () <UINavigationControllerDelegate>

@property (readonly, nonatomic, strong) DWRootModel *model;

@end

@implementation DWRootNavigationController

- (instancetype)init {
    self = [super init];
    if (self) {
        _model = [[DWRootModel alloc] init];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.delegate = self;
    [self setupView];

    if (self.model.hasAWallet) {
        // TODO: impl
    }
    else {
        DWSetupViewController *controller = [DWSetupViewController controllerWithModel:self.model];
        [self pushViewController:controller animated:NO];
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersStatusBarHidden {
    return self.topViewController.prefersStatusBarHidden;
}

#pragma mark - UINavigationControllerDelegate

- (void)navigationController:(UINavigationController *)navigationController
      willShowViewController:(UIViewController *)viewController
                    animated:(BOOL)animated {
    BOOL hidden = [viewController isKindOfClass:DWSetupViewController.class];
    [navigationController setNavigationBarHidden:hidden animated:animated];

    // Hide back button title
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithTitle:@" "
                                                             style:UIBarButtonItemStylePlain
                                                            target:nil
                                                            action:nil];
    viewController.navigationItem.backBarButtonItem = item;
}

#pragma mark - Private

- (void)setupView {
    self.navigationBar.barStyle = UIBarStyleDefault;
    self.navigationBar.barTintColor = [UIColor dw_dashBlueColor];
    self.navigationBar.tintColor = [UIColor dw_tintColor];
    self.navigationBar.translucent = NO;

    self.navigationBar.titleTextAttributes = @{
        NSForegroundColorAttributeName : [UIColor dw_lightTitleColor],
        NSFontAttributeName : [UIFont dw_navigationBarTitleFont],
    };

    [self.navigationBar setBackgroundImage:[[UIImage alloc] init] forBarMetrics:UIBarMetricsDefault];
    self.navigationBar.shadowImage = [[UIImage alloc] init];
}

@end

NS_ASSUME_NONNULL_END

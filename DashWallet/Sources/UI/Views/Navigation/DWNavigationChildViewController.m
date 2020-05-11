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

#import "DWNavigationChildViewController.h"

#import "UINavigationBar+DWAppearance.h"

@implementation DWNavigationChildViewController

- (DWNavigationBarAppearance)navigationBarAppearance {
    return DWNavigationBarAppearanceDefault;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSAssert(self.navigationController,
             @"DWNavigationChildViewController is intended to use within UINavigationController hierarchy");
}

- (void)willMoveToParentViewController:(UIViewController *)parent {
    [super willMoveToParentViewController:parent];

    NSArray<UIViewController *> *viewControllers = self.navigationController.viewControllers;
    UIViewController *last = viewControllers.lastObject;
    if (last == self && viewControllers.count > 1) {
        UIViewController *previous = viewControllers[viewControllers.count - 2];
        if ([previous isKindOfClass:DWNavigationChildViewController.class]) {
            [(DWNavigationChildViewController *)previous setNavigationBarAppearance];
        }
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self setNavigationBarAppearance];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    UIViewController *previous = self.navigationController.viewControllers.lastObject;
    if ([previous isKindOfClass:DWNavigationChildViewController.class]) {
        [(DWNavigationChildViewController *)previous animateNavigationBarAppearance];
    }
}

#pragma mark - Private

- (void)animateNavigationBarAppearance {
    [self.transitionCoordinator
        animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context) {
            [self setNavigationBarAppearance];
        }
                        completion:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context){
                        }];
}

- (void)setNavigationBarAppearance {
    UINavigationBar *navigationBar = self.navigationController.navigationBar;
    switch (self.navigationBarAppearance) {
        case DWNavigationBarAppearanceDefault:
            [navigationBar dw_configureForDefaultAppearance];
            break;
        case DWNavigationBarAppearanceWhite:
            [navigationBar dw_configureForWhiteAppearance];
            break;
    }

    [self setNeedsStatusBarAppearanceUpdate];
}

@end

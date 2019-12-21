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

#import "DWNavigationController.h"

#import "DWNavigationFullscreenable.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWNavigationController () <UINavigationControllerDelegate>

@property (nullable, weak, nonatomic) id<UINavigationControllerDelegate> realDelegate;

@end

@implementation DWNavigationController

- (void)dealloc {
    self.delegate = nil;
}

- (void)setDelegate:(nullable id<UINavigationControllerDelegate>)delegate {
    [super setDelegate:nil];
    self.realDelegate = delegate != self ? delegate : nil;
    [super setDelegate:delegate ? self : nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [super setDelegate:self];
    [self dwNavigationControllerSetup];
}

- (nullable UIViewController *)childViewControllerForStatusBarStyle {
    return self.topViewController;
}

- (nullable UIViewController *)childViewControllerForStatusBarHidden {
    return self.topViewController;
}

#pragma mark - UINavigationControllerDelegate

- (void)navigationController:(UINavigationController *)navigationController
      willShowViewController:(UIViewController *)viewController
                    animated:(BOOL)animated {
    BOOL hidden = [viewController conformsToProtocol:@protocol(DWNavigationFullscreenable)] &&
                  [(id<DWNavigationFullscreenable>)viewController requiresNoNavigationBar];
    [navigationController setNavigationBarHidden:hidden animated:animated];

    // Hide back button title
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithTitle:@" "
                                                             style:UIBarButtonItemStylePlain
                                                            target:nil
                                                            action:nil];
    item.tintColor = [UIColor dw_tintColor];
    viewController.navigationItem.backBarButtonItem = item;

    id<UINavigationControllerDelegate> delegate = self.realDelegate;
    if ([delegate respondsToSelector:_cmd]) {
        [delegate navigationController:navigationController
                willShowViewController:viewController
                              animated:animated];
    }

    // https://stackoverflow.com/questions/23484310/canceling-interactive-uinavigationcontroller-pop-gesture-does-not-call-uinavigat
    [navigationController.transitionCoordinator
        notifyWhenInteractionChangesUsingBlock:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            if (context.cancelled &&
                [self.realDelegate
                    respondsToSelector:@selector(navigationController:didShowViewController:animated:)]) {
                UIViewController *fromViewController =
                    [context viewControllerForKey:UITransitionContextFromViewControllerKey];

                NSTimeInterval animationCompletion =
                    context.transitionDuration * context.percentComplete + 0.05;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(animationCompletion * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                                   [self.realDelegate navigationController:navigationController didShowViewController:fromViewController animated:animated];
                               });
            }
        }];
}

#pragma mark - Private

- (void)dwNavigationControllerSetup {
    UINavigationBar *navigationBar = self.navigationBar;
    navigationBar.barStyle = UIBarStyleDefault;
    navigationBar.barTintColor = [UIColor dw_dashNavigationBlueColor];
    navigationBar.tintColor = [UIColor dw_tintColor];
    navigationBar.translucent = NO;

    navigationBar.titleTextAttributes = @{
        NSForegroundColorAttributeName : [UIColor dw_lightTitleColor],
        NSFontAttributeName : [UIFont dw_navigationBarTitleFont],
    };

    navigationBar.shadowImage = [[UIImage alloc] init];

    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *standardAppearance = navigationBar.standardAppearance;
        NSParameterAssert(standardAppearance);
        standardAppearance.backgroundColor = navigationBar.barTintColor;
        standardAppearance.titleTextAttributes = navigationBar.titleTextAttributes;
        standardAppearance.shadowImage = navigationBar.shadowImage;
        standardAppearance.shadowColor = [UIColor clearColor];

        UIBarButtonItemAppearance *buttonAppearance = standardAppearance.buttonAppearance;
        NSParameterAssert(buttonAppearance);
        UIBarButtonItemStateAppearance *stateApperance = buttonAppearance.normal;
        stateApperance.titleTextAttributes = navigationBar.titleTextAttributes;

        navigationBar.scrollEdgeAppearance = standardAppearance;
        navigationBar.compactAppearance = standardAppearance;
    }
}

#pragma mark - Delegate Forwarder

// https://github.com/steipete/PSPDFTextView/blob/master/PSPDFTextView/PSPDFTextView.m

- (BOOL)respondsToSelector:(SEL)aSelector {
    return [super respondsToSelector:aSelector] ||
           [self.realDelegate respondsToSelector:aSelector];
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    id delegate = self.realDelegate;

    if ([delegate respondsToSelector:aSelector]) {
        return delegate;
    }
    else {
        return [super forwardingTargetForSelector:aSelector];
    }
}

@end

NS_ASSUME_NONNULL_END

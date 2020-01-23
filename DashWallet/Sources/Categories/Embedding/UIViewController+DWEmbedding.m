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

#import "UIViewController+DWEmbedding.h"

#import "UIView+DWEmbedding.h"

// Based on https://github.com/davedelong/MVCTodo/blob/master/MVCTodo/Extensions/UIViewController.swift

NS_ASSUME_NONNULL_BEGIN

@implementation UIViewController (DWEmbedding)

- (void)dw_embedChild:(UIViewController *)newChild {
    [self dw_embedChild:newChild inContainer:nil];
}

- (void)dw_embedChild:(UIViewController *)newChild inContainer:(nullable UIView *)container {
    // if the view controller is already a child of something else, remove it
    UIViewController *oldParent = newChild.parentViewController;
    if (oldParent && oldParent != self) {
        [self.class dw_detachFromParent:newChild];
    }

    // since .view returns an IUO, by default the type of this is "UIView?"
    // explicitly type the variable because We Know Better™
    UIView *targetContainer = container ?: self.view;
    if ([targetContainer dw_isContainedWithinView:self.view] == NO) {
        targetContainer = self.view;
    }

    // add the view controller as a child
    if (newChild.parentViewController != self) {
        [newChild beginAppearanceTransition:YES animated:NO];
        [self addChildViewController:newChild];
        [targetContainer dw_embedSubview:newChild.view];
        [newChild didMoveToParentViewController:self];
        [newChild endAppearanceTransition];
    }
    else {
        // the viewcontroller is already a child
        // make sure it's in the right view

        // we don't do the appearance transition stuff here,
        // because the vc is already a child, so *presumably*
        // that transition stuff has already happened
        [targetContainer dw_embedSubview:newChild.view];
    }
    newChild.view.preservesSuperviewLayoutMargins = YES;
}

- (void)dw_detachFromParent {
    [self.class dw_detachFromParent:self];
}

#pragma mark - Private

+ (void)dw_detachFromParent:(UIViewController *)controller {
    [controller beginAppearanceTransition:NO animated:NO];
    [controller willMoveToParentViewController:nil];
    [controller removeFromParentViewController];
    [controller.viewIfLoaded removeFromSuperview];
    [controller endAppearanceTransition];
}

@end

NS_ASSUME_NONNULL_END

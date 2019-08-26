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

#ifndef DWAlertInternalConstants_h
#define DWAlertInternalConstants_h

// Default iOS UIAlertController's constants

static CGFloat const DWAlertViewWidth = 270.0;

static CGFloat const DWAlertViewContentHorizontalPadding = 16.0;
static CGFloat const DWAlertViewContentVerticalPadding = 20.0;

static CGFloat const DWAlertViewCornerRadius = 13.0;
static CGFloat const DWAlertViewActionButtonHeight = 44.0;
static CGFloat const DWAlertViewActionsMultilineMinimumHeight = 66.0;

static CGFloat const DWAlertTransitionAnimationDuration = 0.4;
static CGFloat const DWAlertTransitionAnimationDampingRatio = 1.0;
static CGFloat const DWAlertTransitionAnimationInitialVelocity = 0.0;
static UIViewAnimationOptions const DWAlertTransitionAnimationOptions = UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;

static CGFloat const DWAlertInplaceTransitionAnimationDuration = 0.4;
static CGFloat const DWAlertInplaceTransitionAnimationDampingRatio = 1.0;
static CGFloat const DWAlertInplaceTransitionAnimationInitialVelocity = 0.0;
static UIViewAnimationOptions const DWAlertInplaceTransitionAnimationOptions = UIViewAnimationOptionCurveEaseInOut;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused"

static BOOL DWAlertHasTopNotch() {
    if (@available(iOS 11.0, *)) {
        return [UIApplication sharedApplication].delegate.window.safeAreaInsets.bottom > 0.0;
    }

    return NO;
}

static CGFloat DWAlertViewVerticalPadding(CGFloat minInset, BOOL keyboardVisible) {
    CGFloat padding = 0.0;
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        if (keyboardVisible) {
            padding = 20.0;
        }
        else {
            padding = 24.0;
        }
    }
    else {
        if (UIInterfaceOrientationIsPortrait([UIApplication sharedApplication].statusBarOrientation)) {
            BOOL hasTopNotch = DWAlertHasTopNotch();
            if (keyboardVisible) {
                padding = hasTopNotch ? minInset : 20.0;
            }
            else {
                padding = hasTopNotch ? 61.0 : 24.0;
            }
        }
        else {
            padding = 8.0;
        }
    }

    return MAX(padding, minInset);
}

static CGFloat DWAlertViewSeparatorSize() {
    return 1.0 / [UIScreen mainScreen].scale;
}

#pragma clang diagnostic pop

#endif /* DWAlertInternalConstants_h */

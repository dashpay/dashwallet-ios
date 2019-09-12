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

#import "DWModalPopupPresentationController.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWModalPopupPresentationController

- (CGRect)frameOfPresentedViewInContainerView {
    const CGRect bounds = self.containerView.bounds;

    if (self.appearanceStyle == DWModalPopupAppearanceStyle_Fullscreen) {
        return bounds;
    }

    const CGFloat height = CGRectGetHeight(bounds);
    const CGFloat width = CGRectGetWidth(bounds);

    CGFloat viewWidth;
    if (IS_IPAD) {
        viewWidth = width / 2;
    }
    else {
        const CGFloat horizontalPadding = 16.0;
        viewWidth = width - horizontalPadding * 2;
    }

    CGFloat viewHeight;
    if (IS_IPHONE_5_OR_LESS) {
        const CGFloat verticalPadding = 20.0;
        viewHeight = height - verticalPadding * 2;
    }
    else if (IS_IPHONE_6) {
        const CGFloat verticalPadding = 50.0;
        viewHeight = height - verticalPadding * 2;
    }
    else if (IS_IPHONE_6_PLUS) {
        const CGFloat verticalPadding = 90.0;
        viewHeight = height - verticalPadding * 2;
    }
    else {
        const CGFloat heightPercent = 0.68;
        viewHeight = ceil(height * heightPercent);
    }

    const CGRect frame = CGRectMake((width - viewWidth) / 2,
                                    (height - viewHeight) / 2,
                                    viewWidth,
                                    viewHeight);

    return frame;
}

@end

NS_ASSUME_NONNULL_END

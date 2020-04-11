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

#import "UIView+DWEmbedding.h"

// Based on https://github.com/davedelong/MVCTodo/blob/master/MVCTodo/Extensions/UIView.swift

NS_ASSUME_NONNULL_BEGIN

@implementation UIView (DWEmbedding)

- (void)dw_embedSubview:(UIView *)subview {
    // do nothing if this view is already in the right place
    if (subview.superview == self) {
        return;
    }

    if (subview.superview != nil) {
        [subview removeFromSuperview];
    }

    subview.translatesAutoresizingMaskIntoConstraints = NO;
    subview.frame = self.bounds;
    [self addSubview:subview];

    [NSLayoutConstraint activateConstraints:@[
        [subview.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.trailingAnchor constraintEqualToAnchor:subview.trailingAnchor],

        [subview.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.bottomAnchor constraintEqualToAnchor:subview.bottomAnchor],
    ]];
}

- (BOOL)dw_isContainedWithinView:(UIView *)other {
    UIView *current = self;
    while (current != nil) {
        if (current == other) {
            return YES;
        }

        current = current.superview;
    }

    return NO;
}

- (void)dw_removeAllSubviews {
    [self.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
}

@end

NS_ASSUME_NONNULL_END

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

#import "UIView+DWAutolayout.h"

@implementation UIView (DWAutolayout)

- (NSArray<NSLayoutConstraint *> *)pinHorizontally:(id<DWHorizontalAnchors>)horizontalAnchors {
    return [self pinHorizontally:horizontalAnchors left:0 right:0 except:-1];
}

- (NSArray<NSLayoutConstraint *> *)pinHorizontally:(id<DWHorizontalAnchors>)horizontalAnchors
                                              left:(CGFloat)left
                                             right:(CGFloat)right {
    return [self pinHorizontally:horizontalAnchors left:left right:right except:-1];
}

- (NSArray<NSLayoutConstraint *> *)pinHorizontally:(id<DWHorizontalAnchors>)horizontalAnchors
                                              left:(CGFloat)left
                                             right:(CGFloat)right
                                            except:(DWAnchor)exceptAnchor {
    NSAssert(self.translatesAutoresizingMaskIntoConstraints == NO,
             @"translatesAutoresizingMaskIntoConstraints is invalid");

    NSMutableArray<NSLayoutConstraint *> *res = [NSMutableArray array];

    if (exceptAnchor != DWAnchorLeft) {
        [res addObject:[self.leadingAnchor constraintEqualToAnchor:horizontalAnchors.leadingAnchor constant:left]];
    }

    if (exceptAnchor != DWAnchorRight) {
        [res addObject:[horizontalAnchors.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:right]];
    }

    return res;
}

- (NSArray<NSLayoutConstraint *> *)pinVertically:(id<DWVerticalAnchors>)verticalAnchors {
    return [self pinVertically:verticalAnchors top:0 bottom:0 except:-1];
}

- (NSArray<NSLayoutConstraint *> *)pinVertically:(id<DWVerticalAnchors>)verticalAnchors
                                             top:(CGFloat)top
                                          bottom:(CGFloat)bottom {
    return [self pinVertically:verticalAnchors top:top bottom:bottom except:-1];
}

- (NSArray<NSLayoutConstraint *> *)pinVertically:(id<DWVerticalAnchors>)verticalAnchors
                                             top:(CGFloat)top
                                          bottom:(CGFloat)bottom
                                          except:(DWAnchor)exceptAnchor {
    NSAssert(self.translatesAutoresizingMaskIntoConstraints == NO,
             @"translatesAutoresizingMaskIntoConstraints is invalid");

    NSMutableArray<NSLayoutConstraint *> *res = [NSMutableArray array];

    if (exceptAnchor != DWAnchorTop) {
        [res addObject:[self.topAnchor constraintEqualToAnchor:verticalAnchors.topAnchor constant:top]];
    }

    if (exceptAnchor != DWAnchorBottom) {
        [res addObject:[verticalAnchors.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:bottom]];
    }

    return res;
}

- (NSArray<NSLayoutConstraint *> *)pinEdges:(id<DWAnchors>)anchors {
    return [self pinEdges:anchors insets:UIEdgeInsetsZero except:-1];
}

- (NSArray<NSLayoutConstraint *> *)pinEdges:(id<DWAnchors>)anchors
                                     insets:(UIEdgeInsets)insets {
    return [self pinEdges:anchors insets:insets except:-1];
}

- (NSArray<NSLayoutConstraint *> *)pinEdges:(id<DWAnchors>)anchors
                                     insets:(UIEdgeInsets)insets
                                     except:(DWAnchor)exceptAnchor {
    NSAssert(self.translatesAutoresizingMaskIntoConstraints == NO,
             @"translatesAutoresizingMaskIntoConstraints is invalid");

    NSMutableArray<NSLayoutConstraint *> *res = [NSMutableArray array];

    [res addObjectsFromArray:[self pinHorizontally:anchors left:insets.left right:insets.right except:exceptAnchor]];
    [res addObjectsFromArray:[self pinVertically:anchors top:insets.top bottom:insets.bottom except:exceptAnchor]];

    return res;
}

- (NSArray<NSLayoutConstraint *> *)pinSize:(CGSize)size {
    NSAssert(self.translatesAutoresizingMaskIntoConstraints == NO,
             @"translatesAutoresizingMaskIntoConstraints is invalid");

    return @[
        [self.widthAnchor constraintEqualToConstant:size.width],
        [self.heightAnchor constraintEqualToConstant:size.height],
    ];
}

@end

@implementation UILayoutGuide (DWAutolayout)

@end

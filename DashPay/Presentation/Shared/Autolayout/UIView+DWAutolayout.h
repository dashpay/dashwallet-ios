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

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, DWAnchor) {
    DWAnchorTop,
    DWAnchorLeft,
    DWAnchorBottom,
    DWAnchorRight,
};

@protocol DWHorizontalAnchors <NSObject>

@property (nonatomic, readonly, strong) NSLayoutXAxisAnchor *leadingAnchor;
@property (nonatomic, readonly, strong) NSLayoutXAxisAnchor *trailingAnchor;

@end

@protocol DWVerticalAnchors <NSObject>

@property (nonatomic, readonly, strong) NSLayoutYAxisAnchor *topAnchor;
@property (nonatomic, readonly, strong) NSLayoutYAxisAnchor *bottomAnchor;

@end

@protocol DWAnchors <DWHorizontalAnchors, DWVerticalAnchors>
@end

#pragma mark -

@interface UIView (DWAutolayout) <DWAnchors>

- (NSArray<NSLayoutConstraint *> *)pinHorizontally:(id<DWHorizontalAnchors>)horizontalAnchors;
- (NSArray<NSLayoutConstraint *> *)pinHorizontally:(id<DWHorizontalAnchors>)horizontalAnchors
                                              left:(CGFloat)left
                                             right:(CGFloat)right;
- (NSArray<NSLayoutConstraint *> *)pinHorizontally:(id<DWHorizontalAnchors>)horizontalAnchors
                                              left:(CGFloat)left
                                             right:(CGFloat)right
                                            except:(DWAnchor)exceptAnchor;

- (NSArray<NSLayoutConstraint *> *)pinVertically:(id<DWVerticalAnchors>)verticalAnchors;
- (NSArray<NSLayoutConstraint *> *)pinVertically:(id<DWVerticalAnchors>)verticalAnchors
                                             top:(CGFloat)top
                                          bottom:(CGFloat)bottom;
- (NSArray<NSLayoutConstraint *> *)pinVertically:(id<DWVerticalAnchors>)verticalAnchors
                                             top:(CGFloat)top
                                          bottom:(CGFloat)bottom
                                          except:(DWAnchor)exceptAnchor;

- (NSArray<NSLayoutConstraint *> *)pinEdges:(id<DWAnchors>)anchors;
- (NSArray<NSLayoutConstraint *> *)pinEdges:(id<DWAnchors>)anchors
                                     insets:(UIEdgeInsets)insets;
- (NSArray<NSLayoutConstraint *> *)pinEdges:(id<DWAnchors>)anchors
                                     insets:(UIEdgeInsets)insets
                                     except:(DWAnchor)exceptAnchor;

- (NSArray<NSLayoutConstraint *> *)pinSize:(CGSize)size;

@end

@interface UILayoutGuide (DWAutolayout) <DWAnchors>
@end

NS_ASSUME_NONNULL_END

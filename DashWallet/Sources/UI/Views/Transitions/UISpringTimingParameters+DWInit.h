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

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UISpringTimingParameters (DWInit)

- (instancetype)initWithDamping:(CGFloat)damping response:(CGFloat)response;

/**
 A design-friendly way to create a spring timing curve.

 @param damping The 'bounciness' of the animation. Value must be between 0 and 1.
 @param response The 'speed' of the animation. Value must be greater than 0.
 @param velocity The vector describing the starting motion of the property. Optional, default is zero.
 */
- (instancetype)initWithDamping:(CGFloat)damping
                       response:(CGFloat)response
                initialVelocity:(CGVector)velocity;

@end

NS_ASSUME_NONNULL_END

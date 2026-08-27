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

#import "UISpringTimingParameters+DWInit.h"

NS_ASSUME_NONNULL_BEGIN

@implementation UISpringTimingParameters (DWInit)

- (instancetype)initWithDamping:(CGFloat)damping response:(CGFloat)response {
    return [self initWithDamping:damping response:response initialVelocity:CGVectorMake(0.0, 0.0)];
}

- (instancetype)initWithDamping:(CGFloat)damping
                       response:(CGFloat)response
                initialVelocity:(CGVector)velocity {
    NSAssert(response > 0, @"Invalid response");
    if (response <= 0) {
        response = 1.0;
    }

    const CGFloat stiffness = pow(2.0 * M_PI / response, 2.0);
    const CGFloat damp = 4 * M_PI * damping / response;

    return [self initWithMass:1.0 stiffness:stiffness damping:damp initialVelocity:velocity];
}

@end

NS_ASSUME_NONNULL_END

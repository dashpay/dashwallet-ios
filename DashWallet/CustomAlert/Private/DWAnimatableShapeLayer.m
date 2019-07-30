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

#import "DWAnimatableShapeLayer.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWAnimatableShapeLayer ()

@property (null_resettable, strong, nonatomic) NSMutableSet *animatableKeys;

@end

@implementation DWAnimatableShapeLayer

- (void)setAnimationsDisabled {
    [self.animatableKeys removeObject:@"path"];
}

#pragma mark - Private

- (NSMutableSet *)animatableKeys {
    if (!_animatableKeys) {
        _animatableKeys = [NSMutableSet setWithObject:@"path"];
    }
    return _animatableKeys;
}

- (nullable id<CAAction>)actionForKey:(NSString *)event {
    if ([self.animatableKeys containsObject:event]) {
        return [self customAnimationForKey:event];
    }
    return [super actionForKey:event];
}

- (CABasicAnimation *)customAnimationForKey:(NSString *)key {
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:key];
    animation.fromValue = [self.presentationLayer valueForKey:key];
    animation.duration = [CATransaction animationDuration];
    return animation;
}

@end

NS_ASSUME_NONNULL_END

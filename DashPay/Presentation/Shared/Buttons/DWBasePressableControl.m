//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWBasePressableControl.h"

#import "UISpringTimingParameters+DWInit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWBasePressableControl ()

@property (nullable, strong, nonatomic) UIViewPropertyAnimator *animator;

@end

NS_ASSUME_NONNULL_END


@implementation DWBasePressableControl

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self addTarget:self
                      action:@selector(tochDown)
            forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
        [self addTarget:self
                      action:@selector(touchUp)
            forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchDragExit | UIControlEventTouchCancel];
    }
    return self;
}

- (void)tochDown {
    [self.animator stopAnimation:YES];
    self.transform = CGAffineTransformMakeScale(0.95, 0.95);
}

- (void)touchUp {
    UISpringTimingParameters *params = [[UISpringTimingParameters alloc] initWithDamping:0.6 response:0.3];
    self.animator = [[UIViewPropertyAnimator alloc] initWithDuration:0.25 timingParameters:params];
    __weak typeof(self) weakSelf = self;
    [self.animator addAnimations:^{
        weakSelf.transform = CGAffineTransformIdentity;
    }];
    [self.animator startAnimation];
}

@end

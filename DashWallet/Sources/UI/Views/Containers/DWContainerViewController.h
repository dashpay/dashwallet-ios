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

typedef NS_ENUM(NSUInteger, DWContainerTransitionType) {
    DWContainerTransitionType_WithoutAnimation,
    DWContainerTransitionType_CrossDissolve,
    DWContainerTransitionType_ScaleAndCrossDissolve,
};

@interface DWContainerViewController : UIViewController

@property (readonly, nullable, strong, nonatomic) UIViewController *currentController;

@property (readonly, nonatomic, assign) NSTimeInterval transitionAnimationDuration;
@property (readonly, nonatomic, strong) UIView *containerView;

/// Default cross-dissolve transition
- (void)transitionToController:(UIViewController *)controller;

- (void)transitionToController:(UIViewController *)toViewController
                transitionType:(DWContainerTransitionType)transitionType;

@end

NS_ASSUME_NONNULL_END

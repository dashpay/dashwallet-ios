//
//  Created by Andrew Podkovyrin
//  Copyright © 2018 Dash Core Group. All rights reserved.
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

#import "DWAlertAction.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWAlertController : UIViewController

@property (readonly, nullable, strong, nonatomic) UIViewController *contentController;
- (void)setupContentController:(UIViewController *)controller;
- (void)performTransitionToContentController:(UIViewController *)controller;

@property (readonly, copy, nonatomic) NSArray<DWAlertAction *> *actions;
- (void)addAction:(DWAlertAction *)action;
- (void)setupActions:(NSArray<DWAlertAction *> *)actions;

@property (nullable, strong, nonatomic) DWAlertAction *preferredAction;

@end

NS_ASSUME_NONNULL_END

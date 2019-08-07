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

#import "DWShortcutsActionDelegate.h"

NS_ASSUME_NONNULL_BEGIN

@class DWShortcutsModel;
@class DWShortcutsView;

@protocol DWShortcutsViewDelegate <NSObject>

- (void)shortcutsViewDidUpdateContentSize:(DWShortcutsView *)view;

@end

@interface DWShortcutsView : UIView

@property (readonly, strong, nonatomic) DWShortcutsModel *model;
@property (nullable, nonatomic, weak) id<DWShortcutsViewDelegate> delegate;
@property (nullable, nonatomic, weak) id<DWShortcutsActionDelegate> actionDelegate;

@end

NS_ASSUME_NONNULL_END

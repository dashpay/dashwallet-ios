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

#import "DWBaseSeedViewController.h"

#import "DWRecoverAction.h"

NS_ASSUME_NONNULL_BEGIN

@class DWRecoverViewController;

@protocol DWRecoverViewControllerDelegate <NSObject>

- (void)recoverViewControllerDidRecoverWallet:(DWRecoverViewController *)controller;
- (void)recoverViewControllerDidWipe:(DWRecoverViewController *)controller;

@end

@interface DWRecoverViewController : DWBaseSeedViewController

@property (nonatomic, assign) DWRecoverAction action;
@property (nullable, nonatomic, weak) id<DWRecoverViewControllerDelegate> delegate;

@end

NS_ASSUME_NONNULL_END

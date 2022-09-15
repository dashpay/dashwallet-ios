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

#import "DWBaseLegacyViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class DWStartModel;
@protocol DWStartViewControllerDelegate;

@interface DWStartViewController : DWBaseLegacyViewController

@property (strong, nonatomic) DWStartModel *viewModel;
@property (nullable, weak, nonatomic) id<DWStartViewControllerDelegate> delegate;
@property (nullable, nonatomic, strong) NSURL *deferredURLToProcess;

+ (instancetype)controller;

@end

@protocol DWStartViewControllerDelegate <NSObject>

- (void)startViewController:(DWStartViewController *)controller
    didFinishWithDeferredLaunchOptions:(NSDictionary *)launchOptions
                shouldRescanBlockchain:(BOOL)shouldRescanBlockchain;

@end

NS_ASSUME_NONNULL_END

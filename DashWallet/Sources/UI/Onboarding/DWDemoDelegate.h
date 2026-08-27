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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class UIViewController;

/// In Demo Mode we can't use default presenting logic since UIKit creates separate transition view for that
/// outside of ours miniWalletView, so no transformation will be applied for presenting controller
@protocol DWDemoDelegate <NSObject>

- (void)presentModalController:(UIViewController *)controller sender:(UIViewController *)sender;

@end

NS_ASSUME_NONNULL_END

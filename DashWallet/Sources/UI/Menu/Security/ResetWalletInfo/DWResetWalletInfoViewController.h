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

#import "DWWipeDelegate.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWResetWalletInfoViewController : UIViewController

@property (nullable, nonatomic, weak) id<DWWipeDelegate> delegate;

+ (instancetype)controller NS_SWIFT_NAME(make());

@end

NS_ASSUME_NONNULL_END
